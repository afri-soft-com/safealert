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
 * Android 8+ locks channel sound at first creation. Never reuse sos_alerts /
 * safealert_sos_*_v1 if they were created without custom sound — bump the id.
 */
const SOS_CHANNEL_ID = "safealert_sos_siren_v2";
const SOS_CHANNEL_ID_LEGACY = "sos_alerts";
const SOS_CHANNEL_ID_V2 = "safealert_sos_siren_v2";
const DEFAULT_CHANNEL_ID = "safealert_general_v2";
const SOS_SOUND_ANDROID = "safealert_siren";
// Match apns.js — system default is reliable when the app is killed.
const SOS_SOUND_IOS = (process.env.SOS_IOS_SOUND || "default").trim() || "default";
const DEFAULT_SOUND_ANDROID = "safealert_beacon";
const DEFAULT_SOUND_IOS =
  (process.env.DEFAULT_IOS_SOUND || "default").trim() || "default";

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
    // Unique per incident — collapsing all "sos_alert" into one key dropped
    // undelivered alerts when the phone was asleep.
    const collapseId = String(
      data?.incidentId ||
        data?.groupId ||
        `${data?.type || "safealert"}-${Date.now()}`
    ).slice(0, 64);
    const message = {
      token,
      data,
      notification: payload.notification || {
        title: data?.title || "SafeAlert",
        body: data?.body || "",
      },
      android: {
        // HIGH is required to wake Doze / turn the screen on when app is killed.
        priority: "high",
        // Was 60s — messages expired before Doze delivered them (screen stayed off).
        ttl: isSos ? 24 * 60 * 60 * 1000 : 7 * 24 * 60 * 60 * 1000,
        collapseKey: collapseId,
        notification: {
          channelId: isSos ? SOS_CHANNEL_ID : DEFAULT_CHANNEL_ID,
          sound: isSos ? SOS_SOUND_ANDROID : DEFAULT_SOUND_ANDROID,
          defaultVibrateTimings: true,
          defaultLightSettings: true,
          priority: isSos ? "max" : "high",
          visibility: "public",
          notificationCount: 1,
        },
      },
      apns: {
        headers: {
          // 10 = immediate delivery (required for audible alerts when app is killed).
          "apns-priority": "10",
          "apns-push-type": "alert",
          "apns-expiration": String(Math.floor(Date.now() / 1000) + 86400),
          "apns-collapse-id": collapseId,
        },
        payload: {
          aps: {
            // Visible banner + sound when app is terminated. Do NOT set
            // content-available here — silent wakes are dropped after force-quit.
            alert: {
              title:
                payload.notification?.title || data?.title || "SafeAlert",
              body: payload.notification?.body || data?.body || "",
            },
            sound: isSos ? SOS_SOUND_IOS : DEFAULT_SOUND_IOS,
            badge: 1,
          },
        },
      },
    };
    const msg = await fcm.messaging().send(message);
    return msg;
  } catch (err) {
    const code = err?.errorInfo?.code || err?.code || "";
    // Expected for every iOS token until an APNs key is uploaded in Firebase Console.
    // Closed-app iOS delivery uses direct APNs (APNS_* env) instead.
    if (code === "messaging/third-party-auth-error") {
      warn(
        "FCM→iOS blocked (Invalid APNs credential in Firebase). Relying on direct APNs."
      );
      return null;
    }
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
