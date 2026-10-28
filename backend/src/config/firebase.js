const admin = require("firebase-admin");
const { log, warn, error: logError } = require("../utils/logger");

let fcm = null;

/** Types data FCM critiques → canal Android max + son custom. */
const SOS_PUSH_TYPES = new Set([
  "sos_alert",
  "nearby_alert",
  "group_sos",
  "group_report",
  "sector_sos",
  "trust_zone_alert",
  "safety_ping_ask",
  "safety_ping_missed",
]);

/**
 * Prefer sticky legacy channel so ALL installed builds receive SOS
 * (new builds also create safealert_sos_*_v1 + re-create sos_alerts with siren).
 */
const SOS_CHANNEL_ID = "sos_alerts";
const SOS_CHANNEL_ID_LEGACY = "sos_alerts";
const SOS_CHANNEL_ID_V2 = "safealert_sos_siren_v1";
const DEFAULT_CHANNEL_ID = "safealert_general_v1";
const SOS_SOUND_ANDROID = "safealert_siren";
const SOS_SOUND_IOS = "safealert_siren.caf";
const DEFAULT_SOUND_ANDROID = "safealert_beacon";
const DEFAULT_SOUND_IOS = "safealert_beacon.caf";

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

const stringifyData = (data) => {
  if (!data || typeof data !== "object") return undefined;
  const out = {};
  for (const [k, v] of Object.entries(data)) {
    if (v === undefined || v === null) continue;
    out[k] = String(v);
  }
  return out;
};

const sendPush = async (token, payload) => {
  if (!fcm) return null;
  try {
    const data = stringifyData({
      ...(payload.data || {}),
      // Mirror notification fields into data so background/data handlers can play sound
      // even when the OS consumes the system tray notification.
      title: payload.notification?.title || payload.data?.title,
      body: payload.notification?.body || payload.data?.body,
    });
    const isSos = data?.type && SOS_PUSH_TYPES.has(data.type);
    const message = {
      token,
      data,
      notification: payload.notification,
      android: {
        priority: "high",
        ttl: isSos ? 60 * 1000 : undefined,
        notification: {
          channelId: isSos ? SOS_CHANNEL_ID : DEFAULT_CHANNEL_ID,
          sound: isSos ? SOS_SOUND_ANDROID : DEFAULT_SOUND_ANDROID,
          defaultVibrateTimings: true,
          priority: isSos ? "max" : "high",
          ...(isSos
            ? {
                visibility: "public",
                defaultSound: false,
                notificationCount: 1,
              }
            : {}),
        },
      },
      apns: {
        headers: {
          "apns-priority": "10",
          ...(isSos ? { "apns-push-type": "alert" } : {}),
        },
        payload: {
          aps: {
            sound: isSos ? SOS_SOUND_IOS : DEFAULT_SOUND_IOS,
            ...(isSos
              ? {
                  "interruption-level": "time-sensitive",
                  "mutable-content": 1,
                }
              : {}),
          },
        },
      },
    };
    const msg = await fcm.messaging().send(message);
    return msg;
  } catch (err) {
    const code = err?.errorInfo?.code || err?.code || "";
    // Stale tokens: clear is handled elsewhere; log for ops.
    logError("FCM send error:", code || err.message, err?.errorInfo || "");
    return null;
  }
};

const isFcmConfigured = () => Boolean(fcm);

module.exports = {
  initFCM,
  sendPush,
  isFcmConfigured,
  SOS_PUSH_TYPES,
  SOS_CHANNEL_ID,
  SOS_CHANNEL_ID_LEGACY,
  DEFAULT_CHANNEL_ID,
  SOS_SOUND_ANDROID,
  SOS_SOUND_IOS,
};
