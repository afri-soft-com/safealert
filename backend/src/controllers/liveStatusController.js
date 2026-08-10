const { pool } = require("../config/database");
const { liveStatus } = require("../config/features");

const TTL_SECONDS = 90;

const upsertLiveStatus = async (req, res) => {
  if (!liveStatus()) return res.status(503).json({ error: "Statut live désactivé" });

  const { incident_id, lat, lng, battery_pct, accuracy_m } = req.body;
  if (!incident_id || lat == null || lng == null) {
    return res.status(400).json({ error: "incident_id et position requis" });
  }

  try {
    const inc = await pool.query(
      `SELECT id, user_id, status FROM incidents
       WHERE id = $1 AND user_id = $2 AND status IN ('active','acknowledged','in_progress')
         AND severity = 'alert'`,
      [incident_id, req.userId]
    );
    if (inc.rows.length === 0) {
      return res.status(404).json({ error: "SOS actif non trouvé" });
    }

    const result = await pool.query(
      `INSERT INTO sos_live_status (incident_id, user_id, lat, lng, battery_pct, accuracy_m, expires_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, NOW() + ($7 * INTERVAL '1 second'), NOW())
       ON CONFLICT (incident_id) DO UPDATE SET
         lat = EXCLUDED.lat, lng = EXCLUDED.lng,
         battery_pct = EXCLUDED.battery_pct, accuracy_m = EXCLUDED.accuracy_m,
         expires_at = EXCLUDED.expires_at, updated_at = NOW()
       RETURNING *`,
      [
        incident_id, req.userId, lat, lng,
        battery_pct != null ? Math.min(100, Math.max(0, parseInt(battery_pct))) : null,
        accuracy_m || null,
        TTL_SECONDS,
      ]
    );

    const io = req.app.get("io");
    if (io) {
      io.emit("sos_live", {
        incident_id,
        user_id: req.userId,
        lat, lng,
        battery_pct: result.rows[0].battery_pct,
        expires_at: result.rows[0].expires_at,
      });
    }

    return res.json({ status: result.rows[0], ttl_seconds: TTL_SECONDS });
  } catch (err) {
    console.error("upsertLiveStatus error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const getLiveStatus = async (req, res) => {
  if (!liveStatus()) return res.status(503).json({ error: "Statut live désactivé" });
  const { incidentId } = req.params;

  try {
    const result = await pool.query(
      `SELECT s.*, u.pseudo
       FROM sos_live_status s
       JOIN users u ON u.id = s.user_id
       WHERE s.incident_id = $1 AND s.expires_at > NOW()`,
      [incidentId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Statut expiré ou introuvable" });
    }

    // Only trust contacts / leaders / self
    const row = result.rows[0];
    if (row.user_id !== req.userId) {
      const allowed = await pool.query(
        `SELECT 1 FROM trust_contacts
         WHERE user_id = $1 AND contact_user_id = $2
         UNION ALL
         SELECT 1 FROM users WHERE id = $2 AND role IN ('leader','agent','platform_admin')`,
        [row.user_id, req.userId]
      );
      if (allowed.rows.length === 0) {
        return res.status(403).json({ error: "Accès refusé" });
      }
    }

    return res.json(row);
  } catch (err) {
    console.error("getLiveStatus error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const purgeExpired = async () => {
  await pool.query(`DELETE FROM sos_live_status WHERE expires_at < NOW()`);
};

module.exports = { upsertLiveStatus, getLiveStatus, purgeExpired, TTL_SECONDS };
