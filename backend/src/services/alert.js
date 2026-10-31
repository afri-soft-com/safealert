const { pool } = require("../config/database");
const { sendSMS } = require("./sms");
const { cacheGet, cacheSet, isRedisReady } = require("../config/redis");
const { phoneLookupVariants } = require("../utils/phone");
const { sendPushToUser } = require("./pushTargets");

const ALERT_RADIUS_KM = 0.5;
const NEARBY_CACHE_KEY = "alerts:nearby_users";
const NEARBY_CACHE_TTL = 30;

const resolveContactUserId = async (client, contactPhone) => {
  const variants = phoneLookupVariants(contactPhone);
  if (!variants.length) return null;
  const res = await client.query(
    `SELECT id FROM users WHERE phone = ANY($1::text[]) LIMIT 1`,
    [variants]
  );
  return res.rows[0]?.id || null;
};

const notifyContacts = async (
  client,
  userId,
  user,
  messageTitle,
  messageBody,
  smsBody,
  dataType,
  extraData = {}
) => {
  const contactsResult = await client.query(
    `SELECT tc.contact_name, tc.contact_phone
     FROM trust_contacts tc
     WHERE tc.user_id = $1`,
    [userId]
  );

  let pushSent = 0;
  let smsSent = 0;
  for (const contact of contactsResult.rows) {
    const contactUserId = await resolveContactUserId(client, contact.contact_phone);
    if (contactUserId && String(contactUserId) === String(userId)) {
      continue;
    }
    if (contactUserId) {
      const n = await sendPushToUser(contactUserId, {
        notification: { title: messageTitle, body: messageBody },
        data: {
          type: dataType,
          userId: String(userId),
          pseudo: user.pseudo ? String(user.pseudo) : "",
          phone: user.phone ? String(user.phone) : "",
          ...extraData,
        },
      });
      if (n > 0) pushSent += 1;
    }
    try {
      const smsRes = await sendSMS(contact.contact_phone, smsBody);
      // Count only real deliveries (not console simulation / failed fallback).
      if (smsRes && !smsRes.simulated && !smsRes.failed) smsSent += 1;
    } catch (err) {
      console.error("SOS contact SMS failed:", err.message);
    }
  }

  console.log("SOS contacts notified", {
    contacts: contactsResult.rows.length,
    pushSent,
    smsSent,
  });
  return {
    contacts: contactsResult.rows.length,
    pushSent,
    smsSent,
  };
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

  // Haversine approx in meters (avoids broken geometry casts on last_lat/lng columns).
  const nearbyResult = await client.query(
    `SELECT u.id, u.fcm_token, u.phone, u.last_lat, u.last_lng
     FROM users u
     WHERE u.id != $1
       AND u.last_lat IS NOT NULL
       AND u.last_lng IS NOT NULL
       AND u.last_seen_at > NOW() - INTERVAL '30 minutes'
       AND (
         6371000 * acos(
           least(1.0, greatest(-1.0,
             cos(radians($2)) * cos(radians(u.last_lat))
             * cos(radians(u.last_lng) - radians($3))
             + sin(radians($2)) * sin(radians(u.last_lat))
           ))
         )
       ) <= $4`,
    [userId, lat, lng, ALERT_RADIUS_KM * 1000]
  );

  if (isRedisReady()) {
    await cacheSet(NEARBY_CACHE_KEY, JSON.stringify(nearbyResult.rows), NEARBY_CACHE_TTL);
  }

  return nearbyResult.rows;
};

const formatCoords = (lat, lng) => {
  const la = Number(lat);
  const ln = Number(lng);
  if (!Number.isFinite(la) || !Number.isFinite(ln)) return "";
  return `${la.toFixed(4)}, ${ln.toFixed(4)}`;
};

const placeLabel = (zoneName) => {
  const z = typeof zoneName === "string" ? zoneName.trim() : "";
  return z || "Lieu en cours de résolution";
};

const locationSnippet = (lat, lng, zoneName) => {
  const place = placeLabel(zoneName);
  const coords = formatCoords(lat, lng);
  return coords ? `${place} · ${coords}` : place;
};

const sendAlert = async (userId, lat, lng, incidentType, zoneName = null, incidentId = null) => {
  const client = await pool.connect();
  try {
    const userResult = await client.query(
      "SELECT pseudo, phone FROM users WHERE id = $1",
      [userId]
    );
    const user = userResult.rows[0];
    if (!user) throw new Error("Utilisateur non trouvé");

    const where = locationSnippet(lat, lng, zoneName);
    const maps = `https://maps.google.com/?q=${lat},${lng}`;
    const locationData = {
      lat: String(lat ?? ""),
      lng: String(lng ?? ""),
      zone_name: zoneName ? String(zoneName) : "",
      incidentType: incidentType ? String(incidentType) : "sos",
      incidentId: incidentId != null ? String(incidentId) : "",
    };

    const contactStats = await notifyContacts(
      client,
      userId,
      user,
      "🚨 SOS — contact d'urgence",
      `${user.pseudo} a déclenché un SOS. ${where}`,
      `🔴 SOS SafeAlert (contact d'urgence) — ${user.pseudo} a besoin d'aide ! Lieu : ${where}. Carte : ${maps}`,
      "sos_alert",
      locationData
    );

    const nearbyUsers = await getNearbyUsers(client, userId, lat, lng);
    let nearbyPush = 0;

    for (const nu of nearbyUsers) {
      const n = await sendPushToUser(nu.id, {
        notification: {
          title: "🏘️ Signalement — quartier",
          body: `${user.pseudo} a signalé un incident près de vous — ${where}`,
        },
        data: {
          type: "nearby_alert",
          userId: String(userId),
          pseudo: user.pseudo ? String(user.pseudo) : "",
          phone: user.phone ? String(user.phone) : "",
          origin: "quartier",
          ...locationData,
        },
      });
      if (n > 0) nearbyPush += 1;
    }

    return {
      contactsNotified: contactStats.contacts,
      contactsPush: contactStats.pushSent,
      contactsSms: contactStats.smsSent,
      nearbyNotified: nearbyUsers.length,
      nearbyPush,
    };
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

    const contactStats = await notifyContacts(
      client,
      userId,
      user,
      "✅ Fausse alerte — SOS annulé",
      `${user.pseudo} a annulé son SOS (contact d'urgence). Situation sous contrôle.`,
      `✅ FAUSSE ALERTE SafeAlert (contact) — ${user.pseudo} a annulé son SOS. Situation sous contrôle.`,
      "false_alarm",
      {
        lat: String(lat ?? ""),
        lng: String(lng ?? ""),
        origin: "contact",
      }
    );

    const nearbyUsers = await getNearbyUsers(client, userId, lat, lng);

    for (const nu of nearbyUsers) {
      await sendPushToUser(nu.id, {
        notification: {
          title: "✅ Fausse alerte — quartier",
          body: `${user.pseudo} a annulé l'alerte de proximité. Situation sous contrôle.`,
        },
        data: {
          type: "false_alarm",
          userId: String(userId),
          pseudo: user.pseudo ? String(user.pseudo) : "",
          phone: user.phone ? String(user.phone) : "",
          lat: String(lat ?? ""),
          lng: String(lng ?? ""),
          origin: "quartier",
        },
      });
    }

    return {
      contactsNotified: contactStats.contacts,
      contactsPush: contactStats.pushSent,
      contactsSms: contactStats.smsSent,
      nearbyNotified: nearbyUsers.length,
    };
  } finally {
    client.release();
  }
};

module.exports = { sendAlert, sendCancelAlert, ALERT_RADIUS_KM };
