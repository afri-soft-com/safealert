const admin = require("firebase-admin");
const { log, warn, error: logError } = require("../utils/logger");

let fcm = null;

const initFCM = () => {
  const projectId = process.env.FCM_PROJECT_ID || process.env.FIREBASE_PROJECT_ID;
  const privateKey = process.env.FCM_PRIVATE_KEY || process.env.FIREBASE_PRIVATE_KEY;
  const clientEmail = process.env.FCM_CLIENT_EMAIL || process.env.FIREBASE_CLIENT_EMAIL;
  if (projectId && privateKey && clientEmail) {
    fcm = admin.initializeApp({
      credential: admin.credential.cert({
        projectId,
        privateKey: privateKey.replace(/\\n/g, "\n"),
        clientEmail,
      }),
    });
    log("Firebase FCM initialized");
  } else {
    warn("FCM not configured — push notifications disabled (set FCM_* or FIREBASE_* env vars)");
  }
};

const sendPush = async (token, payload) => {
  if (!fcm) return null;
  try {
    const msg = await fcm.messaging().send({ token, data: payload.data, notification: payload.notification });
    return msg;
  } catch (err) {
    console.error("FCM send error:", err);
    return null;
  }
};

module.exports = { initFCM, sendPush };
