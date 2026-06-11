const admin = require("firebase-admin");
const { log, warn, error: logError } = require("../utils/logger");

let fcm = null;

const initFCM = () => {
  const { FCM_PROJECT_ID, FCM_PRIVATE_KEY, FCM_CLIENT_EMAIL } = process.env;
  if (FCM_PROJECT_ID && FCM_PRIVATE_KEY && FCM_CLIENT_EMAIL) {
    fcm = admin.initializeApp({
      credential: admin.credential.cert({
        projectId: FCM_PROJECT_ID,
        privateKey: FCM_PRIVATE_KEY.replace(/\\n/g, "\n"),
        clientEmail: FCM_CLIENT_EMAIL,
      }),
    });
    log("Firebase FCM initialized");
  } else {
    warn("FCM not configured — push notifications disabled");
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
