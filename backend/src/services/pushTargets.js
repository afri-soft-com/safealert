const { pool } = require("../config/database");
const { sendPush } = require("../config/firebase");
const { sendApns, isApnsConfigured } = require("../config/apns");

/**
 * Per-device targets. Prefer direct APNs on iOS when configured so killed-app
 * delivery works without a Firebase Console APNs key — but ALWAYS fall back to
 * FCM if APNs fails (sandbox/prod mismatch, BadDeviceToken, etc.).
 */
const getUserPushTargets = async (userId) => {
  const devices = [];
  const fcmSeen = new Set();
  try {
    const rows = await pool.query(
      `SELECT fcm_token, apns_token FROM user_devices
       WHERE user_id = $1 AND revoked_at IS NULL`,
      [userId]
    );
    for (const row of rows.rows) {
      const fcm = row.fcm_token || null;
      const apns = row.apns_token || null;
      if (!fcm && !apns) continue;
      devices.push({ fcm, apns });
      if (fcm) fcmSeen.add(fcm);
    }
  } catch (_) {
    try {
      const rows = await pool.query(
        `SELECT fcm_token FROM user_devices
         WHERE user_id = $1 AND revoked_at IS NULL
           AND fcm_token IS NOT NULL AND fcm_token <> ''`,
        [userId]
      );
      for (const row of rows.rows) {
        if (!row.fcm_token) continue;
        devices.push({ fcm: row.fcm_token, apns: null });
        fcmSeen.add(row.fcm_token);
      }
    } catch (__) {
      /* table may be absent briefly */
    }
  }

  try {
    const user = await pool.query(`SELECT fcm_token FROM users WHERE id = $1`, [userId]);
    const legacy = user.rows[0]?.fcm_token;
    if (legacy && !fcmSeen.has(legacy)) {
      devices.push({ fcm: legacy, apns: null });
    }
  } catch (_) {
    /* ignore */
  }

  return devices;
};

/** @deprecated flat FCM list — prefer getUserPushTargets */
const getUserPushTokens = async (userId) => {
  const devices = await getUserPushTargets(userId);
  return [...new Set(devices.map((d) => d.fcm).filter(Boolean))];
};

const sendPushToUser = async (userId, payload) => {
  const devices = await getUserPushTargets(userId);
  const apnsOk = isApnsConfigured();
  let sent = 0;

  for (const device of devices) {
    // Dual-path for iOS: APNs direct AND FCM in parallel.
    // Previously APNs "success" skipped FCM — if the token was stale or the
    // host mismatched, the user got nothing. Duplicate banners on SOS are
    // preferable to silent failure.
    const tasks = [];
    if (apnsOk && device.apns) {
      tasks.push(
        sendApns(device.apns, payload).then((ok) => Boolean(ok))
      );
    }
    if (device.fcm) {
      tasks.push(sendPush(device.fcm, payload).then((ok) => Boolean(ok)));
    }
    if (!tasks.length) continue;

    const results = await Promise.all(tasks);
    if (results.some(Boolean)) sent += 1;
  }
  return sent;
};

module.exports = { getUserPushTokens, getUserPushTargets, sendPushToUser };
