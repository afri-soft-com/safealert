const { pool } = require("../config/database");
const { sendPush } = require("../config/firebase");

/** Collect FCM tokens for a user (multi-device + legacy column). */
const getUserPushTokens = async (userId) => {
  const tokens = new Set();
  try {
    const devices = await pool.query(
      `SELECT fcm_token FROM user_devices
       WHERE user_id = $1 AND revoked_at IS NULL AND fcm_token IS NOT NULL AND fcm_token <> ''`,
      [userId]
    );
    for (const row of devices.rows) {
      if (row.fcm_token) tokens.add(row.fcm_token);
    }
  } catch (_) {
    /* table may be absent briefly */
  }
  try {
    const user = await pool.query(`SELECT fcm_token FROM users WHERE id = $1`, [userId]);
    if (user.rows[0]?.fcm_token) tokens.add(user.rows[0].fcm_token);
  } catch (_) {
    /* ignore */
  }
  return [...tokens];
};

const sendPushToUser = async (userId, payload) => {
  const tokens = await getUserPushTokens(userId);
  for (const token of tokens) {
    await sendPush(token, payload);
  }
  return tokens.length;
};

module.exports = { getUserPushTokens, sendPushToUser };
