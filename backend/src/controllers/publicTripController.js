const { pool } = require("../config/database");
const { publicShare, safeTrip } = require("../config/features");

/** Public read-only trip follow by short token (no auth). */
const getPublicTrip = async (req, res) => {
  if (!safeTrip() || !publicShare()) {
    return res.status(503).json({ error: "Suivi public désactivé" });
  }
  const token = String(req.params.token || "").trim();
  if (!token || token.length < 8) {
    return res.status(400).json({ error: "Lien invalide" });
  }

  try {
    const result = await pool.query(
      `SELECT t.id, t.status, t.dest_label, t.eta_at,
              t.origin_lat, t.origin_lng, t.dest_lat, t.dest_lng,
              t.last_lat, t.last_lng, t.last_ping_at, t.abnormal_stop_at,
              t.share_expires_at, t.created_at, t.arrived_at,
              u.pseudo AS traveler_pseudo
       FROM safe_trips t
       JOIN users u ON u.id = t.user_id
       WHERE t.share_token = $1
         AND t.share_expires_at > NOW()
         AND t.status IN ('active','arrived','alerted')`,
      [token]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Lien expiré ou trajet introuvable" });
    }
    const trip = result.rows[0];
    return res.json({
      trip: {
        ...trip,
        // Never expose user_id or escort ids publicly
      },
      read_only: true,
    });
  } catch (err) {
    console.error("getPublicTrip error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = { getPublicTrip };
