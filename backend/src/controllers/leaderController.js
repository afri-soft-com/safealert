const { pool } = require("../config/database");

const getSectorIncidents = async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT i.id, i.incident_type, i.description, i.lat, i.lng,
             i.severity, i.status, i.verified_by, i.is_anonymous, i.zone_name, i.created_at,
             i.acknowledged_by, i.acknowledged_at,
             COALESCE(u.pseudo, 'Anonyme') as reporter
      FROM incidents i
      LEFT JOIN users u ON i.user_id = u.id
      WHERE i.status IN ('active', 'verified', 'acknowledged', 'in_progress')
      ORDER BY i.created_at DESC LIMIT 100
    `);
    return res.json(result.rows);
  } catch (err) {
    console.error("getSectorIncidents error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const acknowledgeIncident = async (req, res) => {
  const { id } = req.params;
  try {
    const current = await pool.query("SELECT status FROM incidents WHERE id = $1", [id]);
    if (current.rows.length === 0) {
      return res.status(404).json({ error: "Incident non trouvé" });
    }

    const status = current.rows[0].status;
    let newStatus;
    if (status === "active" || status === "verified") {
      newStatus = "acknowledged";
    } else if (status === "acknowledged") {
      newStatus = "in_progress";
    } else {
      return res.status(400).json({ error: "Cet incident ne peut pas être pris en charge" });
    }

    const result = await pool.query(
      `UPDATE incidents SET status = $2, acknowledged_by = $3, acknowledged_at = NOW()
       WHERE id = $1 RETURNING *`,
      [id, newStatus, req.userId]
    );

    const io = req.app.get("io");
    if (io) {
      io.emit("incident_status", {
        id,
        status: newStatus,
        leader_id: req.userId,
      });
    }

    return res.json({ message: "Prise en charge enregistrée", incident: result.rows[0] });
  } catch (err) {
    console.error("acknowledgeIncident error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const resolveIncident = async (req, res) => {
  const { id } = req.params;
  try {
    const result = await pool.query(
      `UPDATE incidents SET status = 'resolved', resolved_at = NOW()
       WHERE id = $1 AND status IN ('active', 'verified', 'acknowledged', 'in_progress') RETURNING *`,
      [id]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: "Incident non trouvé ou déjà résolu" });
    return res.json({ message: "Incident résolu", incident: result.rows[0] });
  } catch (err) {
    console.error("resolveIncident error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const getSectorStats = async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT
        COUNT(*) FILTER (WHERE status = 'active') as active,
        COUNT(*) FILTER (WHERE status = 'verified') as verified,
        COUNT(*) FILTER (WHERE status = 'acknowledged') as acknowledged,
        COUNT(*) FILTER (WHERE status = 'in_progress') as in_progress,
        COUNT(*) FILTER (WHERE status = 'resolved') as resolved,
        COUNT(*) FILTER (WHERE status = 'false_alarm') as false_alarm,
        COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '24 hours') as last_24h,
        COUNT(DISTINCT user_id) as total_reporters
      FROM incidents
    `);
    return res.json(result.rows[0]);
  } catch (err) {
    console.error("getSectorStats error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

module.exports = { getSectorIncidents, acknowledgeIncident, resolveIncident, getSectorStats };
