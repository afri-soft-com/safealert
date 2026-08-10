const { pool } = require("../config/database");
const { sendPush } = require("../config/firebase");
const { sendSMS } = require("./sms");
const { cacheGet, cacheSet, isRedisReady } = require("../config/redis");

const ALERT_RADIUS_KM = 0.5;
const NEARBY_CACHE_KEY = "alerts:nearby_users";
const NEARBY_CACHE_TTL = 30;

const notifyContacts = async (client, userId, user, messageTitle, messageBody, smsBody, dataType) => {
  const contactsResult = await client.query(
    `SELECT tc.contact_name, tc.contact_phone, u.fcm_token, u.id as contact_user_id
     FROM trust_contacts tc
     LEFT JOIN users u ON tc.contact_phone = u.phone
     WHERE tc.user_id = $1`,
    [userId]
  );

  for (const contact of contactsResult.rows) {
    if (contact.contact_user_id && contact.fcm_token) {
      await sendPush(contact.fcm_token, {
        notification: { title: messageTitle, body: messageBody },
        data: { type: dataType, userId: String(userId) },
      });
    }
    await sendSMS(contact.contact_phone, smsBody);
  }

  return contactsResult.rows.length;
};

const getNearbyUsers = async (client, userId, lat, lng) => {
  if (isRedisReady()) {
    const cached = await cacheGet(NEARBY_CACHE_KEY);
    if (cached) {
      try {
        const users = JSON.parse(cached);
        return users.filter((u) => u.id !== userId);
      } catch (_) {}
    }
  }

  const nearbyResult = await client.query(
    `SELECT u.id, u.fcm_token, u.phone, u.last_lat, u.last_lng
     FROM users u
     WHERE u.id != $1
       AND u.last_lat IS NOT NULL
       AND u.last_lng IS NOT NULL
       AND ST_DWithin(
         u.last_lng::text::geometry,
         ST_MakePoint($3, $2)::geography,
         $4
       )
       AND u.last_seen_at > NOW() - INTERVAL '30 minutes'`,
    [userId, lat, lng, ALERT_RADIUS_KM * 1000]
  );

  if (isRedisReady()) {
    await cacheSet(NEARBY_CACHE_KEY, JSON.stringify(nearbyResult.rows), NEARBY_CACHE_TTL);
  }

  return nearbyResult.rows;
};

const sendAlert = async (userId, lat, lng, incidentType) => {
  const client = await pool.connect();
  try {
    const userResult = await client.query(
      "SELECT pseudo, phone FROM users WHERE id = $1",
      [userId]
    );
    const user = userResult.rows[0];
    if (!user) throw new Error("Utilisateur non trouvé");

    const contactsNotified = await notifyContacts(
      client,
      userId,
      user,
      "🚨 Alerte SafeAlert",
      `${user.pseudo} a besoin d'aide ! (${incidentType})`,
      `🔴 ALERTE SafeAlert — ${user.pseudo} a besoin d'aide ! Position: https://maps.google.com/?q=${lat},${lng}`,
      "sos_alert"
    );

    const nearbyUsers = await getNearbyUsers(client, userId, lat, lng);

    for (const nu of nearbyUsers) {
      if (nu.fcm_token) {
        await sendPush(nu.fcm_token, {
          notification: {
            title: "🚨 Alerte dans votre quartier",
            body: `${user.pseudo} signale un incident à proximité !`,
          },
          data: {
            type: "nearby_alert",
            userId: String(userId),
            lat: String(lat),
            lng: String(lng),
            incidentType,
          },
        });
      }
    }

    return { contactsNotified, nearbyNotified: nearbyUsers.length };
  } finally {
    client.release();
  }
};

const sendCancelAlert = async (userId, lat, lng) => {
  const client = await pool.connect();
  try {
    const userResult = await client.query(
      "SELECT pseudo, phone FROM users WHERE id = $1",
      [userId]
    );
    const user = userResult.rows[0];
    if (!user) return { contactsNotified: 0, nearbyNotified: 0 };

    const contactsNotified = await notifyContacts(
      client,
      userId,
      user,
      "✅ Fausse alerte — SafeAlert",
      `${user.pseudo} : fausse alerte. Situation sous contrôle, aucune intervention nécessaire.`,
      `✅ FAUSSE ALERTE SafeAlert — ${user.pseudo} a annulé son SOS. Situation sous contrôle.`,
      "false_alarm"
    );

    const nearbyUsers = await getNearbyUsers(client, userId, lat, lng);

    for (const nu of nearbyUsers) {
      if (nu.fcm_token) {
        await sendPush(nu.fcm_token, {
          notification: {
            title: "Fausse alerte — quartier",
            body: `${user.pseudo} : fausse alerte. Situation sous contrôle.`,
          },
          data: {
            type: "false_alarm",
            userId: String(userId),
          },
        });
      }
    }

    return { contactsNotified, nearbyNotified: nearbyUsers.length };
  } finally {
    client.release();
  }
};

module.exports = { sendAlert, sendCancelAlert, ALERT_RADIUS_KM };
