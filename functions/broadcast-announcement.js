const admin = require("firebase-admin");
const functions = require("firebase-functions");

exports.broadcastAnnouncement = functions.firestore
  .document("announcements/{docId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const db = admin.firestore();

    const usersSnap = await db.collection("users").get();
    const staffSnap = await db.collection("healthcarestaff").get();
    const caregiverSnap = await db.collection("caregiver").get();

    const allUids = new Set([
      ...usersSnap.docs.map((d) => d.id),
      ...staffSnap.docs.map((d) => d.id),
      ...caregiverSnap.docs.map((d) => d.id),
    ]);

    const botUid = "system_aura_guide";

    await db.collection("healthcarestaff").doc(botUid).set(
      {
        staffId: "SYS001",
        name: "Aura Guide",
        role: "System",
        status: "Active",
        email: "system@auraguide.com",
      },
      { merge: true },
    );

    const chunks = [];
    let currentBatch = db.batch();
    let batchCount = 0;

    const commitBatch = async () => {
      if (batchCount > 0) {
        chunks.push(currentBatch.commit());
        currentBatch = db.batch();
        batchCount = 0;
      }
    };

    const messageText = data.message || "";
    const title = data.title || "Announcement";
    const content = `📢 **${title}**\n\n${messageText}`;

    for (const uid of allUids) {
      if (uid === botUid) continue;

      const conversationId = `sys_ag_${uid}`;
      const conversationRef = db.collection("conversations").doc(conversationId);

      currentBatch.set(
        conversationRef,
        {
          conversationId,
          participant1Id: botUid,
          participant2Id: uid,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          status: "Active",
        },
        { merge: true },
      );
      batchCount++;

      const messageRef = conversationRef.collection("messages").doc();
      currentBatch.set(messageRef, {
        senderId: botUid,
        receiverId: uid,
        content: content,
        type: "text",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        status: "sent",
      });
      batchCount++;

      if (batchCount >= 400) {
        await commitBatch();
      }
    }

    await commitBatch();
    await Promise.all(chunks);
  });
