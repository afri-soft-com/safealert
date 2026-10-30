const { pool } = require("../config/database");
const { sendPush } = require("../config/firebase");
const { neighborhoodWatch } = require("../config/features");
const { sendSMS, isSMSConfigured } = require("../services/sms");

const DIGEST_MINUTE_SLOTS = [0, 15, 30, 45];

/** Parse digest hour 0–23. `0` is valid (midnight). Invalid → null. */
function parseDigestHour(value) {
  if (value === undefined || value === null || value === "") return null;
  const n = Number.parseInt(value, 10);
  if (!Number.isFinite(n) || n < 0 || n > 23) return null;
  return n;
}

/** Parse digest minute — only 0 / 15 / 30 / 45. Default 0 when omitted. */
function parseDigestMinute(value, { required = false } = {}) {
  if (value === undefined || value === null || value === "") {
    return required ? null : 0;
  }
  const n = Number.parseInt(value, 10);
  if (!Number.isFinite(n) || !DIGEST_MINUTE_SLOTS.includes(n)) return null;
  return n;
}

/** Current hour + minute in Africa/Kinshasa (UTC+1, no DST). */
function kinshasaParts(date = new Date()) {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Africa/Kinshasa",
    hour: "numeric",
    minute: "numeric",
    hourCycle: "h23",
  }).formatToParts(date);
  const hourRaw = parts.find((p) => p.type === "hour")?.value;
  const minuteRaw = parts.find((p) => p.type === "minute")?.value;
  const hour = Number.parseInt(hourRaw, 10);
  const minute = Number.parseInt(minuteRaw, 10);
  return {
    hour: Number.isFinite(hour) ? hour % 24 : 0,
    minute: Number.isFinite(minute) ? minute % 60 : 0,
  };
}

/** Current hour in Africa/Kinshasa (UTC+1, no DST). */
function kinshasaHour(date = new Date()) {
  return kinshasaParts(date).hour;
}

/** 15-minute slot for a clock minute (0, 15, 30, 45). */
function minuteSlot(minute) {
  const m = Number.isFinite(minute) ? minute : 0;
  return Math.floor(m / 15) * 15;
}

/** Normalize free-text quartier for ILIKE matching. */
function normalizeQuartier(q) {
  return String(q || "")
    .trim()
    .replace(/\s+/g, " ");
}

async function deliverDigest(sub) {
  const q = normalizeQuartier(sub.quartier);
  const stats = await pool.query(
    `SELECT COUNT(*)::int AS total,
            COUNT(*) FILTER (WHERE severity = 'alert')::int AS sos
     FROM incidents
     WHERE zone_name ILIKE $1
       AND created_at > NOW() - INTERVAL '24 hours'`,
    [`%${q}%`]
  );
  const { total, sos } = stats.rows[0];
  const title = `Digest — ${q}`;
  const body = `${total} incident(s) dont ${sos} SOS sur 24h.`;
  let delivered = false;

  if (sub.fcm_token) {
    try {
      await sendPush(sub.fcm_token, {
        notification: { title: `🏘️ ${title}`, body },
        data: { type: "neighborhood_digest", quartier: q },
      });
      delivered = true;
    } catch (err) {
      console.error("neighborhood push error:", err.message);
    }
  }

  if (!delivered && isSMSConfigured() && sub.phone) {
    try {
      await sendSMS(sub.phone, `SafeAlert ${title}: ${body}`);
      delivered = true;
    } catch (err) {
      console.error("neighborhood sms error:", err.message);
    }
  }

  if (delivered) {
    await pool.query(
      `UPDATE neighborhood_subscriptions SET last_digest_at = NOW() WHERE id = $1`,
      [sub.id]
    );
  }
  return { delivered, title, body, total, sos };
}

const subscribe = async (req, res) => {
  if (!neighborhoodWatch()) {
    return res.status(503).json({ error: "Veille de quartier désactivée" });
  }
  const { quartier, digest_hour, digest_minute } = req.body;
  const q = normalizeQuartier(quartier);
  if (!q || q.length < 2) {
    return res.status(400).json({ error: "Nom de quartier requis" });
  }
  const hour =
    digest_hour === undefined || digest_hour === null || digest_hour === ""
      ? 18
      : parseDigestHour(digest_hour);
  if (hour === null) {
    return res.status(400).json({ error: "Heure du résumé invalide (0–23)" });
  }
  const minute = parseDigestMinute(digest_minute);
  if (minute === null) {
    return res.status(400).json({ error: "Minutes invalides (0, 15, 30 ou 45)" });
  }
  try {
    const result = await pool.query(
      `INSERT INTO neighborhood_subscriptions (user_id, quartier, digest_hour, digest_minute)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id, quartier) DO UPDATE
         SET digest_hour = EXCLUDED.digest_hour,
             digest_minute = EXCLUDED.digest_minute
       RETURNING *`,
      [req.userId, q, hour, minute]
    );
    return res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error("neighborhood subscribe error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const updateSubscription = async (req, res) => {
  if (!neighborhoodWatch()) {
    return res.status(503).json({ error: "Veille de quartier désactivée" });
  }
  if (req.body.digest_hour === undefined || req.body.digest_hour === null || req.body.digest_hour === "") {
    return res.status(400).json({ error: "Heure du résumé requise (0–23)" });
  }
  const hour = parseDigestHour(req.body.digest_hour);
  if (hour === null) {
    return res.status(400).json({ error: "Heure du résumé invalide (0–23)" });
  }
  const minute = parseDigestMinute(req.body.digest_minute);
  if (minute === null) {
    return res.status(400).json({ error: "Minutes invalides (0, 15, 30 ou 45)" });
  }
  try {
    const result = await pool.query(
      `UPDATE neighborhood_subscriptions
       SET digest_hour = $1, digest_minute = $2
       WHERE id = $3 AND user_id = $4 RETURNING *`,
      [hour, minute, req.params.id, req.userId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Abonnement introuvable" });
    }
    return res.json(result.rows[0]);
  } catch (err) {
    console.error("neighborhood update error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const unsubscribe = async (req, res) => {
  if (!neighborhoodWatch()) {
    return res.status(503).json({ error: "Veille de quartier désactivée" });
  }
  try {
    await pool.query(
      `DELETE FROM neighborhood_subscriptions WHERE id = $1 AND user_id = $2`,
      [req.params.id, req.userId]
    );
    return res.json({ message: "Désabonnement effectué" });
  } catch (err) {
    console.error("neighborhood unsubscribe error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const listSubscriptions = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT * FROM neighborhood_subscriptions WHERE user_id = $1 ORDER BY created_at DESC`,
      [req.userId]
    );
    return res.json(result.rows);
  } catch (err) {
    console.error("listSubscriptions error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

/** Immediate digest for QA — bypasses schedule, still requires FCM/SMS. */
const sendNow = async (req, res) => {
  if (!neighborhoodWatch()) {
    return res.status(503).json({ error: "Veille de quartier désactivée" });
  }
  try {
    const sub = await pool.query(
      `SELECT ns.*, u.fcm_token, u.phone
       FROM neighborhood_subscriptions ns
       JOIN users u ON u.id = ns.user_id
       WHERE ns.id = $1 AND ns.user_id = $2`,
      [req.params.id, req.userId]
    );
    if (sub.rows.length === 0) {
      return res.status(404).json({ error: "Abonnement introuvable" });
    }
    const result = await deliverDigest(sub.rows[0]);
    if (!result.delivered) {
      return res.status(502).json({
        error:
          "Résumé non envoyé : activez les notifications push (ou SMS) sur cet appareil.",
      });
    }
    return res.json({
      message: "Résumé envoyé",
      total: result.total,
      sos: result.sos,
      body: result.body,
    });
  } catch (err) {
    console.error("neighborhood sendNow error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

/** Send daily digests for subscriptions matching Kinshasa hour + 15-min slot. */
const sendDigests = async (date = new Date()) => {
  if (!neighborhoodWatch()) return { sent: 0 };
  const { hour, minute } = kinshasaParts(date);
  const slot = minuteSlot(minute);
  const subs = await pool.query(
    `SELECT ns.*, u.fcm_token, u.phone FROM neighborhood_subscriptions ns
     JOIN users u ON u.id = ns.user_id
     WHERE ns.digest_hour = $1
       AND COALESCE(ns.digest_minute, 0) = $2
       AND (ns.last_digest_at IS NULL OR ns.last_digest_at < NOW() - INTERVAL '20 hours')`,
    [hour, slot]
  );

  let sent = 0;
  for (const sub of subs.rows) {
    const result = await deliverDigest(sub);
    if (result.delivered) sent += 1;
  }
  return { sent, hour, minute: slot };
};

module.exports = {
  subscribe,
  updateSubscription,
  unsubscribe,
  listSubscriptions,
  sendNow,
  sendDigests,
  parseDigestHour,
  parseDigestMinute,
  kinshasaHour,
  kinshasaParts,
  minuteSlot,
  normalizeQuartier,
  DIGEST_MINUTE_SLOTS,
};
