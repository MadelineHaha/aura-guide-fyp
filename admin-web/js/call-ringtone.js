/** Outgoing ringback (du-du-du) and incoming ring (ring-ring-ring) call tones. */
export class CallRingtone {
  /**
   * @param {"outgoing" | "incoming"} mode
   */
  constructor(mode = "outgoing") {
    this.mode = mode;
    this.audioContext = null;
    this.intervalId = null;
    this.active = false;
  }

  start() {
    if (this.active) return;
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtx) return;

    this.active = true;
    this.audioContext = new AudioCtx();
    void this.audioContext.resume();
    this.playCycle();
    const intervalMs = this.mode === "incoming" ? 4500 : 2800;
    this.intervalId = window.setInterval(() => this.playCycle(), intervalMs);
  }

  playCycle() {
    if (!this.audioContext || !this.active) return;
    if (this.mode === "incoming") {
      this.playIncomingCycle();
    } else {
      this.playOutgoingCycle();
    }
  }

  playOutgoingCycle() {
    const base = this.audioContext.currentTime;
    [0, 0.42, 0.84].forEach((offset) => {
      this.playTone(base + offset, 0.22, 425, 0.58);
      this.playTone(base + offset + 0.04, 0.22, 475, 0.46);
    });
  }

  playIncomingCycle() {
    const base = this.audioContext.currentTime;
    [0, 1.05, 2.1].forEach((offset) => {
      this.playRing(base + offset, 0.62, 480, 0.22);
    });
  }

  playTone(start, duration, frequency, peakGain) {
    const osc = this.audioContext.createOscillator();
    const gain = this.audioContext.createGain();
    osc.type = "sine";
    osc.frequency.value = frequency;
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.exponentialRampToValueAtTime(peakGain, start + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + duration);
    osc.connect(gain);
    gain.connect(this.audioContext.destination);
    osc.start(start);
    osc.stop(start + duration + 0.05);
  }

  playRing(start, duration, frequency, peakGain) {
    const osc = this.audioContext.createOscillator();
    const gain = this.audioContext.createGain();
    osc.type = "sine";
    osc.frequency.value = frequency;
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.exponentialRampToValueAtTime(peakGain, start + 0.04);
    gain.gain.setValueAtTime(peakGain * 0.92, start + duration * 0.55);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + duration);
    osc.connect(gain);
    gain.connect(this.audioContext.destination);
    osc.start(start);
    osc.stop(start + duration + 0.05);
  }

  stop() {
    this.active = false;
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
    if (this.audioContext) {
      void this.audioContext.close();
      this.audioContext = null;
    }
  }
}
