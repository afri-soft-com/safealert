const { pool } = require("../config/database");

const getLeaderSector = async (userId) => {
  const res = await pool.query("SELECT sector_name FROM users WHERE id = $1", [userId]);
  return res.rows[0]?.sector_name || null;
};

const sectorFilterClause = (sectorName, alias = "i", startParam = 1) => {
  if (!sectorName) return { clause: "", params: [], nextParam: startParam };
  return {
    clause: ` AND ${alias}.zone_name ILIKE $${startParam}`,
    params: [`%${sectorName}%`],
    nextParam: startParam + 1,
  };
};

const getSectorIncidents = async (req, res) => {
  try {
    const sectorName = await getLeaderSector(req.userId);
    const filter = sectorFilterClause(sectorName, "i", 1);
    const result = await pool.query(`
      SELECT i.id, i.incident_type, i.description, i.lat, i.lng,
             i.severity, i.status, i.verified_by, i.is_anonymous, i.zone_name, i.created_at,
             i.acknowledged_by, i.acknowledged_at,
             COALESCE(u.pseudo, 'Anonyme') as reporter
      FROM incidents i
      LEFT JOIN users u ON i.user_id = u.id
      WHERE i.status IN ('active', 'verified', 'acknowledged', 'in_progress')
      ${filter.clause}
      ORDER BY i.created_at DESC LIMIT 100
    `, filter.params);
    return res.json(result.rows);
  } catch (err) {
    console.error("getSectorIncidents error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
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
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const resolveIncident = async (req, res) => {
  const { id } = req.params;
  try {
    const existing = await pool.query(
      "SELECT id, zone_name FROM incidents WHERE id = $1 AND status IN ('active', 'verified', 'acknowledged', 'in_progress')",
      [id]
    );
    if (existing.rows.length === 0) {
      return res.status(404).json({ error: "Incident non trouvé ou déjà résolu" });
    }

    const zoneName = existing.rows[0].zone_name;
    let severityUpdate = "";
    if (zoneName) {
      const activeInZone = await pool.query(
        `SELECT COUNT(*)::int AS count FROM incidents
         WHERE zone_name ILIKE $1 AND id != $2
           AND status IN ('active', 'verified', 'acknowledged', 'in_progress')
           AND created_at > NOW() - INTERVAL '24 hours'`,
        [`%${zoneName}%`, id]
      );
      if (activeInZone.rows[0].count === 0) {
        severityUpdate = ", severity = 'safe'";
      }
    }

    const result = await pool.query(
      `UPDATE incidents SET status = 'resolved', resolved_at = NOW()${severityUpdate}
       WHERE id = $1 RETURNING *`,
      [id]
    );
    return res.json({ message: "Incident résolu", incident: result.rows[0] });
  } catch (err) {
    console.error("resolveIncident error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const getSectorStats = async (req, res) => {
  try {
    const sectorName = await getLeaderSector(req.userId);
    let whereClause = "";
    const params = [];
    if (sectorName) {
      whereClause = " WHERE zone_name ILIKE $1";
      params.push(`%${sectorName}%`);
    }

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
      ${whereClause}
    `, params);
    return res.json({ ...result.rows[0], sector_name: sectorName });
  } catch (err) {
    console.error("getSectorStats error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = { getSectorIncidents, acknowledgeIncident, resolveIncident, getSectorStats };
