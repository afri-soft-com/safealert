const { pool } = require("../config/database");
const { sendPush } = require("../config/firebase");
const { neighborhoodWatch } = require("../config/features");
const { sendSMS, isSMSConfigured } = require("../services/sms");

/** Parse digest hour 0–23. `0` is valid (midnight). Invalid → null. */
function parseDigestHour(value) {
  if (value === undefined || value === null || value === "") return null;
  const n = Number.parseInt(value, 10);
  if (!Number.isFinite(n) || n < 0 || n > 23) return null;
  return n;
}

/** Current hour in Africa/Kinshasa (UTC+1, no DST). */
function kinshasaHour(date = new Date()) {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Africa/Kinshasa",
    hour: "numeric",
    hourCycle: "h23",
  }).formatToParts(date);
  const raw = parts.find((p) => p.type === "hour")?.value;
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) ? n % 24 : 0;
}

/** Normalize free-text quartier for ILIKE matching. */
function normalizeQuartier(q) {
  return String(q || "")
    .trim()
    .replace(/\s+/g, " ");
}

const subscribe = async (req, res) => {
  if (!neighborhoodWatch()) {
    return res.status(503).json({ error: "Veille de quartier désactivée" });
  }
  const { quartier, digest_hour } = req.body;
  const q = normalizeQuartier(quartier);
  if (!q || q.length < 2) {
    return res.status(400).json({ error: "Nom de quartier requis" });
  }
  const hour = digest_hour === undefined || digest_hour === null || digest_hour === ""
    ? 18
    : parseDigestHour(digest_hour);
  if (hour === null) {
    return res.status(400).json({ error: "Heure du résumé invalide (0–23)" });
  }
  try {
    const result = await pool.query(
      `INSERT INTO neighborhood_subscriptions (user_id, quartier, digest_hour)
       VALUES ($1, $2, $3)
       ON CONFLICT (user_id, quartier) DO UPDATE SET digest_hour = EXCLUDED.digest_hour
       RETURNING *`,
      [req.userId, q, hour]
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
  try {
    const result = await pool.query(
      `UPDATE neighborhood_subscriptions SET digest_hour = $1
       WHERE id = $2 AND user_id = $3 RETURNING *`,
      [hour, req.params.id, req.userId]
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

/** Send daily digests for subscriptions matching Kinshasa hour. */
const sendDigests = async () => {
  if (!neighborhoodWatch()) return { sent: 0 };
  const hour = kinshasaHour();
  const subs = await pool.query(
    `SELECT ns.*, u.fcm_token, u.phone FROM neighborhood_subscriptions ns
     JOIN users u ON u.id = ns.user_id
     WHERE ns.digest_hour = $1
       AND (ns.last_digest_at IS NULL OR ns.last_digest_at < NOW() - INTERVAL '20 hours')`,
    [hour]
  );

  let sent = 0;
  for (const sub of subs.rows) {
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
        sent += 1;
      } catch (err) {
        console.error("neighborhood push error:", err.message);
      }
    }

    if (!delivered && isSMSConfigured() && sub.phone) {
      try {
        await sendSMS(sub.phone, `SafeAlert ${title}: ${body}`);
        delivered = true;
        sent += 1;
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
  }
  return { sent, hour };
};

module.exports = {
  subscribe,
  updateSubscription,
  unsubscribe,
  listSubscriptions,
  sendDigests,
  parseDigestHour,
  kinshasaHour,
  normalizeQuartier,
};
