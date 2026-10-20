const { pool } = require("../config/database");
const { sendPush } = require("../config/firebase");
const { communeBroadcast } = require("../config/features");
const { sendSMS, isSMSConfigured } = require("../services/sms");

const listBroadcasts = async (req, res) => {
  if (!communeBroadcast()) {
    return res.status(503).json({ error: "Broadcasts désactivés" });
  }
  try {
    const r = await pool.query(
      `SELECT * FROM commune_broadcasts ORDER BY created_at DESC LIMIT 50`
    );
    return res.json(r.rows);
  } catch (err) {
    console.error("listBroadcasts error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const createBroadcast = async (req, res) => {
  if (!communeBroadcast()) {
    return res.status(503).json({ error: "Broadcasts désactivés" });
  }
  const title = String(req.body.title || "").trim().slice(0, 120);
  const body = String(req.body.body || "").trim().slice(0, 500);
  const zone = String(req.body.zone_name || "").trim().slice(0, 120);
  const channels = String(req.body.channels || "fcm").toLowerCase();
  if (title.length < 3 || body.length < 3 || zone.length < 2) {
    return res.status(400).json({ error: "Titre, message et commune requis" });
  }

  try {
    const users = await pool.query(
      `SELECT DISTINCT u.id, u.fcm_token, u.phone
       FROM users u
       LEFT JOIN neighborhood_subscriptions ns ON ns.user_id = u.id
       WHERE u.is_active IS DISTINCT FROM false
         AND (
           ns.quartier ILIKE $1
           OR EXISTS (
             SELECT 1 FROM incidents i
             WHERE i.user_id = u.id AND i.zone_name ILIKE $1
               AND i.created_at > NOW() - INTERVAL '30 days'
           )
           OR EXISTS (
             SELECT 1 FROM trust_zones tz
             WHERE tz.user_id = u.id AND tz.label ILIKE $1
           )
         )`,
      [`%${zone}%`]
    );

    let sent = 0;
    const useFcm = channels.includes("fcm") || channels.includes("push");
    const useSms = channels.includes("sms") && isSMSConfigured();

    for (const u of users.rows) {
      let ok = false;
      if (useFcm && u.fcm_token) {
        try {
          await sendPush(u.fcm_token, {
            notification: { title: `📢 ${title}`, body },
            data: { type: "commune_broadcast", zone_name: zone },
          });
          ok = true;
        } catch (_) {
          /* continue */
        }
      }
      if (!ok && useSms && u.phone) {
        try {
          await sendSMS(u.phone, `SafeAlert ${title}: ${body}`);
          ok = true;
        } catch (_) {
          /* continue */
        }
      }
      if (ok) sent += 1;
    }

    const saved = await pool.query(
      `INSERT INTO commune_broadcasts (created_by, title, body, zone_name, channels, sent_count)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [req.userId, title, body, zone, channels, sent]
    );
    return res.status(201).json({ broadcast: saved.rows[0], targeted: users.rows.length, sent });
  } catch (err) {
    console.error("createBroadcast error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = { listBroadcasts, createBroadcast };
