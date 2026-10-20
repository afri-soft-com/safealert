const { pool } = require("../config/database");
const { sosPublicShare, liveStatus } = require("../config/features");

/** Public read-only SOS live follow by short token (no auth). */
const getPublicSos = async (req, res) => {
  if (!sosPublicShare()) {
    return res.status(503).json({ error: "Suivi public SOS désactivé" });
  }
  const token = String(req.params.token || "").trim();
  if (!token || token.length < 8) {
    return res.status(400).json({ error: "Lien invalide" });
  }

  try {
    const result = await pool.query(
      `SELECT i.id, i.status, i.incident_type, i.lat, i.lng, i.zone_name,
              i.created_at, i.share_expires_at,
              u.pseudo AS reporter_pseudo
       FROM incidents i
       LEFT JOIN users u ON u.id = i.user_id
       WHERE i.share_token = $1
         AND i.share_expires_at > NOW()
         AND i.status IN ('active','verified','acknowledged','in_progress')
         AND i.severity = 'alert'`,
      [token]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Lien expiré ou alerte introuvable" });
    }
    const incident = result.rows[0];
    let live = null;
    if (liveStatus()) {
      const liveRes = await pool.query(
        `SELECT lat, lng, battery, updated_at, expires_at
         FROM sos_live_status
         WHERE incident_id = $1 AND expires_at > NOW()
         ORDER BY updated_at DESC LIMIT 1`,
        [incident.id]
      );
      live = liveRes.rows[0] || null;
    }
    return res.json({
      incident: {
        status: incident.status,
        incident_type: incident.incident_type,
        lat: live?.lat ?? incident.lat,
        lng: live?.lng ?? incident.lng,
        zone_name: incident.zone_name,
        created_at: incident.created_at,
        share_expires_at: incident.share_expires_at,
        reporter_pseudo: incident.reporter_pseudo,
        battery: live?.battery ?? null,
        live_updated_at: live?.updated_at ?? null,
      },
      read_only: true,
    });
  } catch (err) {
    console.error("getPublicSos error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = { getPublicSos };
