const { pool } = require("../config/database");
const { sendPush } = require("../config/firebase");
const { neighborhoodWatch } = require("../config/features");

const subscribe = async (req, res) => {
  if (!neighborhoodWatch()) {
    return res.status(503).json({ error: "Veille de quartier désactivée" });
  }
  const { quartier, digest_hour } = req.body;
  if (!quartier || String(quartier).trim().length < 2) {
    return res.status(400).json({ error: "Nom de quartier requis" });
  }
  try {
    const result = await pool.query(
      `INSERT INTO neighborhood_subscriptions (user_id, quartier, digest_hour)
       VALUES ($1, $2, $3)
       ON CONFLICT (user_id, quartier) DO UPDATE SET digest_hour = EXCLUDED.digest_hour
       RETURNING *`,
      [
        req.userId,
        String(quartier).trim(),
        Math.min(23, Math.max(0, parseInt(digest_hour) || 18)),
      ]
    );
    return res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error("neighborhood subscribe error:", err);
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

/** Send daily digests for subscriptions matching current hour. */
const sendDigests = async () => {
  if (!neighborhoodWatch()) return { sent: 0 };
  const hour = new Date().getHours();
  const subs = await pool.query(
    `SELECT ns.*, u.fcm_token FROM neighborhood_subscriptions ns
     JOIN users u ON u.id = ns.user_id
     WHERE ns.digest_hour = $1
       AND (ns.last_digest_at IS NULL OR ns.last_digest_at < NOW() - INTERVAL '20 hours')`,
    [hour]
  );

  let sent = 0;
  for (const sub of subs.rows) {
    const stats = await pool.query(
      `SELECT COUNT(*)::int AS total,
              COUNT(*) FILTER (WHERE severity = 'alert')::int AS sos
       FROM incidents
       WHERE zone_name ILIKE $1
         AND created_at > NOW() - INTERVAL '24 hours'`,
      [`%${sub.quartier}%`]
    );
    const { total, sos } = stats.rows[0];
    if (sub.fcm_token) {
      await sendPush(sub.fcm_token, {
        notification: {
          title: `🏘️ Digest — ${sub.quartier}`,
          body: `${total} incident(s) dont ${sos} SOS sur 24h.`,
        },
        data: { type: "neighborhood_digest", quartier: sub.quartier },
      });
      sent += 1;
    }
    await pool.query(
      `UPDATE neighborhood_subscriptions SET last_digest_at = NOW() WHERE id = $1`,
      [sub.id]
    );
  }
  return { sent };
};

module.exports = { subscribe, unsubscribe, listSubscriptions, sendDigests };
