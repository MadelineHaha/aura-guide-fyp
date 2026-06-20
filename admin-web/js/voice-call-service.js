import {
  addDoc,
  collection,
  doc,
  onSnapshot,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { db } from "./firebase.js";

const CALL_SESSIONS_COLLECTION = "callSessions";
const CALL_COUNTER_PATH = ["system", "callCounter"];
const ICE_SERVERS = [{ urls: "stun:stun.l.google.com:19302" }];
const RING_TIMEOUT_MS = 45000;

async function reserveCallId() {
  const counterRef = doc(db, ...CALL_COUNTER_PATH);
  return runTransaction(db, async (transaction) => {
    const counterSnap = await transaction.get(counterRef);
    const next = counterSnap.exists() ? Number(counterSnap.data().next) || 1 : 1;
    const callId = `VC${String(next).padStart(5, "0")}`;
    transaction.set(counterRef, { next: next + 1 }, { merge: true });
    return callId;
  });
}

export class VoiceCallController {
  constructor() {
    this.pc = null;
    this.localStream = null;
    this.remoteAudio = null;
    this.callId = null;
    this.unsubs = [];
    this.ringTimer = null;
    this.connectedAt = null;
    this.onStateChange = null;
    this.state = "idle";
    this.isMuted = false;
    this.isCaller = false;
    this.pendingRemoteCandidates = [];
    this.remoteDescriptionSet = false;
  }

  setRemoteAudioElement(element) {
    this.remoteAudio = element;
    if (this.remoteAudio) {
      this.remoteAudio.autoplay = true;
      this.remoteAudio.playsInline = true;
      this.remoteAudio.volume = 1;
      this.remoteAudio.muted = false;
    }
  }

  attachRemoteStream(event) {
    const stream =
      event.streams?.[0] ||
      (event.track ? new MediaStream([event.track]) : null);
    if (!stream || !this.remoteAudio) return;
    this.remoteAudio.srcObject = stream;
    this.remoteAudio.volume = 1;
    this.remoteAudio.muted = false;
    void this.remoteAudio.play().catch(() => {});
  }

  async addRemoteCandidate(data) {
    if (!this.pc || !data?.candidate) return;
    const candidate = new RTCIceCandidate({
      candidate: data.candidate,
      sdpMid: data.sdpMid ?? null,
      sdpMLineIndex:
        data.sdpMLineIndex == null ? null : Number(data.sdpMLineIndex),
    });
    if (!this.pc.currentRemoteDescription) {
      this.pendingRemoteCandidates.push(candidate);
      return;
    }
    try {
      await this.pc.addIceCandidate(candidate);
    } catch {
      /* ignore late/duplicate candidates */
    }
  }

  async flushPendingCandidates() {
    if (!this.pc?.currentRemoteDescription) return;
    const pending = [...this.pendingRemoteCandidates];
    this.pendingRemoteCandidates = [];
    for (const candidate of pending) {
      try {
        await this.pc.addIceCandidate(candidate);
      } catch {
        /* ignore */
      }
    }
  }

  async setRemoteDescription(description) {
    await this.pc.setRemoteDescription(description);
    this.remoteDescriptionSet = true;
    await this.flushPendingCandidates();
  }

  emit(state, extra = {}) {
    this.state = state;
    this.onStateChange?.({ state, ...extra });
    if (state === "ended") {
      this.state = "idle";
    }
  }

  async startOutgoing({ conversationId, staffId, patientId }) {
    if (!window.RTCPeerConnection) {
      throw new Error("This browser does not support in-app voice calls.");
    }
    if (!navigator.mediaDevices?.getUserMedia) {
      throw new Error("Microphone access is required for voice calls.");
    }

    this.cleanup({ preserveState: true });
    this.isCaller = true;
    this.emit("connecting");

    try {
      this.localStream = await navigator.mediaDevices.getUserMedia({
        audio: true,
        video: false,
      });

      this.pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
      this.localStream
        .getTracks()
        .forEach((track) => this.pc.addTrack(track, this.localStream));

      this.pc.ontrack = (event) => {
        this.attachRemoteStream(event);
        if (!this.connectedAt) {
          this.connectedAt = Date.now();
          this.clearRingTimer();
          this.emit("connected");
          void updateDoc(doc(db, CALL_SESSIONS_COLLECTION, this.callId), {
            status: "active",
            connectedAt: serverTimestamp(),
          });
        }
      };

      this.pc.onicecandidate = (event) => {
        if (!event.candidate || !this.callId) return;
        void addDoc(collection(db, CALL_SESSIONS_COLLECTION, this.callId, "iceCandidates"), {
          from: "staff",
          candidate: event.candidate.candidate,
          sdpMid: event.candidate.sdpMid,
          sdpMLineIndex: event.candidate.sdpMLineIndex,
          createdAt: serverTimestamp(),
        });
      };

      this.callId = await reserveCallId();
      const callRef = doc(db, CALL_SESSIONS_COLLECTION, this.callId);

      await setDoc(callRef, {
        callId: this.callId,
        conversationId,
        staffId,
        patientId,
        status: "ringing",
        initiatedBy: "staff",
        offer: null,
        answer: null,
        createdAt: serverTimestamp(),
      });

      const offer = await this.pc.createOffer({
        offerToReceiveAudio: true,
        offerToReceiveVideo: false,
      });
      await this.pc.setLocalDescription(offer);
      await updateDoc(callRef, {
        offer: { sdp: offer.sdp, type: offer.type },
      });

      this.watchCallSession(callRef);
      this.watchPatientCandidates();

      this.emit("ringing", { callId: this.callId });
      this.ringTimer = setTimeout(() => {
        void this.hangUp({ reason: "missed" });
      }, RING_TIMEOUT_MS);
    } catch (error) {
      this.cleanup();
      throw error;
    }
  }

  watchCallSession(callRef) {
    const unsub = onSnapshot(callRef, (snap) => {
      if (!snap.exists() || !this.pc) return;
      const data = snap.data();
      void this.applyAnswer(data);
      if (data.status === "declined" && this.state !== "ended") {
        void this.hangUp({ reason: "declined", skipRemoteUpdate: true });
      }
      if (
        (data.status === "ended" ||
          data.status === "missed" ||
          data.status === "unanswered") &&
        this.state !== "ended"
      ) {
        void this.hangUp({ reason: data.status, skipRemoteUpdate: true });
      }
    });
    this.unsubs.push(unsub);
  }

  async applyAnswer(data) {
    if (!data?.answer || !this.pc || this.pc.currentRemoteDescription) return;
    try {
      await this.setRemoteDescription(new RTCSessionDescription(data.answer));
    } catch {
      /* ignore duplicate or late answer */
    }
  }

  async answerIncoming({ callId, conversationId, staffId, patientId, offer }) {
    if (!window.RTCPeerConnection) {
      throw new Error("This browser does not support in-app voice calls.");
    }
    if (!navigator.mediaDevices?.getUserMedia) {
      throw new Error("Microphone access is required for voice calls.");
    }
    if (!offer?.sdp || !offer?.type) {
      throw new Error("Incoming call offer is missing.");
    }

    this.cleanup({ preserveState: true });
    this.isCaller = false;
    this.callId = callId;
    this.emit("connecting");

    try {
      this.localStream = await navigator.mediaDevices.getUserMedia({
        audio: true,
        video: false,
      });

      this.pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
      this.localStream
        .getTracks()
        .forEach((track) => this.pc.addTrack(track, this.localStream));

      this.pc.ontrack = (event) => {
        this.attachRemoteStream(event);
        if (!this.connectedAt) {
          this.connectedAt = Date.now();
          this.clearRingTimer();
          this.emit("connected");
        }
      };

      this.pc.onicecandidate = (event) => {
        if (!event.candidate || !this.callId) return;
        void addDoc(collection(db, CALL_SESSIONS_COLLECTION, this.callId, "iceCandidates"), {
          from: "staff",
          candidate: event.candidate.candidate,
          sdpMid: event.candidate.sdpMid,
          sdpMLineIndex: event.candidate.sdpMLineIndex,
          createdAt: serverTimestamp(),
        });
      };

      const callRef = doc(db, CALL_SESSIONS_COLLECTION, callId);
      await this.setRemoteDescription(new RTCSessionDescription(offer));
      const answer = await this.pc.createAnswer({
        offerToReceiveAudio: true,
        offerToReceiveVideo: false,
      });
      await this.pc.setLocalDescription(answer);
      await updateDoc(callRef, {
        answer: { sdp: answer.sdp, type: answer.type },
        status: "active",
        connectedAt: serverTimestamp(),
        conversationId,
        staffId,
        patientId,
      });

      this.watchCallSession(callRef);
      this.watchPatientCandidates();
      this.clearRingTimer();
    } catch (error) {
      this.cleanup();
      throw error;
    }
  }

  async declineIncoming(callId) {
    if (!callId) return;
    try {
      await updateDoc(doc(db, CALL_SESSIONS_COLLECTION, callId), {
        status: "declined",
        endedAt: serverTimestamp(),
        endedBy: "staff",
      });
    } catch {
      /* ignore */
    }
  }

  watchPatientCandidates() {
    if (!this.callId) return;
    const candidatesQuery = query(
      collection(db, CALL_SESSIONS_COLLECTION, this.callId, "iceCandidates"),
      where("from", "==", "patient"),
    );
    const seen = new Set();
    const unsub = onSnapshot(candidatesQuery, (snap) => {
      snap.docs.forEach((docSnap) => {
        if (seen.has(docSnap.id)) return;
        seen.add(docSnap.id);
        void this.addRemoteCandidate(docSnap.data());
      });
    });
    this.unsubs.push(unsub);
  }

  toggleMute() {
    const audioTrack = this.localStream?.getAudioTracks()?.[0];
    if (!audioTrack) return this.isMuted;
    audioTrack.enabled = !audioTrack.enabled;
    this.isMuted = !audioTrack.enabled;
    return this.isMuted;
  }

  getDurationSeconds() {
    if (!this.connectedAt) return 0;
    return Math.max(1, Math.round((Date.now() - this.connectedAt) / 1000));
  }

  async hangUp({ reason = "ended", skipRemoteUpdate = false } = {}) {
    this.clearRingTimer();
    const durationSeconds = this.getDurationSeconds();
    const wasConnected = Boolean(this.connectedAt);

    if (this.callId && !skipRemoteUpdate) {
      try {
        await updateDoc(doc(db, CALL_SESSIONS_COLLECTION, this.callId), {
          status: reason,
          endedAt: serverTimestamp(),
          endedBy: "staff",
          durationSeconds: wasConnected ? durationSeconds : null,
        });
      } catch {
        /* ignore */
      }
    }

    this.cleanup();
    this.emit("ended", {
      reason,
      durationSeconds: wasConnected ? durationSeconds : 0,
      wasConnected,
    });
  }

  clearRingTimer() {
    if (this.ringTimer) {
      clearTimeout(this.ringTimer);
      this.ringTimer = null;
    }
  }

  cleanup({ preserveState = false } = {}) {
    this.clearRingTimer();
    for (const unsub of this.unsubs) unsub();
    this.unsubs = [];
    if (this.localStream) {
      for (const track of this.localStream.getTracks()) track.stop();
    }
    this.localStream = null;
    if (this.pc) {
      this.pc.close();
    }
    this.pc = null;
    this.pendingRemoteCandidates = [];
    this.remoteDescriptionSet = false;
    if (this.remoteAudio) {
      this.remoteAudio.srcObject = null;
    }
    this.callId = null;
    this.connectedAt = null;
    this.isMuted = false;
    this.isCaller = false;
    if (!preserveState) {
      this.state = "idle";
    }
  }
}

export function subscribeStaffIncomingCalls(staffId, { onIncoming, onCleared } = {}) {
  if (!staffId) return () => {};

  const callsQuery = query(
    collection(db, CALL_SESSIONS_COLLECTION),
    where("staffId", "==", staffId),
  );

  return onSnapshot(callsQuery, (snapshot) => {
    let incoming = null;
    for (const docSnap of snapshot.docs) {
      const data = docSnap.data();
      if (data.status !== "ringing") continue;
      if (data.initiatedBy !== "patient") continue;
      if (!data.offer?.sdp || !data.offer?.type) continue;
      incoming = {
        callId: docSnap.id,
        conversationId: data.conversationId,
        staffId: data.staffId,
        patientId: data.patientId,
        offer: data.offer,
      };
      break;
    }

    if (incoming) {
      onIncoming?.(incoming);
    } else {
      onCleared?.();
    }
  });
}
