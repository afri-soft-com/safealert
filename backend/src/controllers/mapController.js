const { pool } = require("../config/database");
const { cacheGet, cacheSet, invalidateActiveAlerts } = require("../config/redis");

const buildIncidentsCacheKey = (hours, status) =>
  `map:incidents:h${hours}:s${status || "all"}`;

const getIncidents = async (req, res) => {
  const { lat, lng, radius_km, status, limit, hours, incident_type } = req.query;
  const hoursVal = Math.min(Math.max(parseInt(hours) || 24, 1), 168);
  const hasGeoFilter = lat && lng && radius_km;

  if (!hasGeoFilter && !incident_type) {
    const cacheKey = buildIncidentsCacheKey(hoursVal, status);
    const cached = await cacheGet(cacheKey);
    if (cached) {
      try {
        return res.json(JSON.parse(cached));
      } catch (_) {}
    }
  }

  try {
    let query = `
      SELECT i.id, i.incident_type, i.description, i.lat, i.lng,
             i.severity, i.status, i.verified_by, i.is_anonymous, i.created_at,
             CASE WHEN i.is_anonymous THEN 'Anonyme' ELSE u.pseudo END as reporter
      FROM incidents i
      JOIN users u ON i.user_id = u.id
      WHERE i.status IN ('active', 'verified', 'acknowledged', 'in_progress')
        AND i.created_at > NOW() - make_interval(hours => $1)
    `;
    const params = [hoursVal];
    let paramIndex = 2;

    if (status) {
      query += ` AND i.status = $${paramIndex++}`;
      params.push(status);
    }

    if (incident_type) {
      query += ` AND i.incident_type = $${paramIndex++}`;
      params.push(incident_type);
    }

    if (hasGeoFilter) {
      query += ` AND ST_DWithin(
        i.lng::text::geometry,
        ST_MakePoint($${paramIndex + 1}, $${paramIndex})::geography,
        $${paramIndex + 2}
      )`;
      params.push(parseFloat(lat), parseFloat(lng), parseFloat(radius_km) * 1000);
      paramIndex += 3;
    }

    query += " ORDER BY i.created_at DESC";
    const limitVal = parseInt(limit) || 100;
    query += ` LIMIT $${paramIndex}`;
    params.push(limitVal);

    const result = await pool.query(query, params);

    if (!hasGeoFilter) {
      const cacheKey = buildIncidentsCacheKey(hoursVal, status);
      await cacheSet(cacheKey, JSON.stringify(result.rows), 60);
    }

    return res.json(result.rows);
  } catch (err) {
    console.error("getIncidents error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const reportIncident = async (req, res) => {
  const { lat, lng, incident_type, description, is_anonymous } = req.body;
  if (!lat || !lng || !incident_type) {
    return res.status(400).json({ error: "Position et type d'incident requis" });
  }
  try {
    const result = await pool.query(
      `INSERT INTO incidents (user_id, incident_type, description, lat, lng, location, severity, is_anonymous)
       VALUES ($1, $2, $3, $4, $5, ST_SetSRID(ST_MakePoint($6, $7), 4326), 'vigilance', $8)
       RETURNING *`,
      [req.userId, incident_type, description, lat, lng, lng, lat, is_anonymous || false]
    );
    await invalidateActiveAlerts();
    return res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error("reportIncident error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const verifyIncident = async (req, res) => {
  const { id } = req.params;
  try {
    const inc = await pool.query("SELECT verified_by, status FROM incidents WHERE id = $1", [id]);
    if (inc.rows.length === 0) return res.status(404).json({ error: "Incident non trouvé" });

    const existing = await pool.query(
      "SELECT id FROM incident_verifications WHERE incident_id = $1 AND user_id = $2",
      [id, req.userId]
    );
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: "Vous avez déjà confirmé cet incident" });
    }

    await pool.query(
      "INSERT INTO incident_verifications (incident_id, user_id) VALUES ($1, $2)",
      [id, req.userId]
    );

    let newStatus = "active";
    const newCount = inc.rows[0].verified_by + 1;
    if (newCount >= 3) newStatus = "verified";

    const result = await pool.query(
      `UPDATE incidents SET verified_by = $1, status = $2 WHERE id = $3 RETURNING *`,
      [newCount, newStatus, id]
    );
    await invalidateActiveAlerts();
    return res.json(result.rows[0]);
  } catch (err) {
    if (err.code === "23505") {
      return res.status(409).json({ error: "Vous avez déjà confirmé cet incident" });
    }
    console.error("verifyIncident error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const getStats = async (req, res) => {
  try {
    const totalRes = await pool.query(`
      SELECT
        COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '7 days') as total_incidents,
        COUNT(*) FILTER (WHERE severity = 'alert' AND created_at > NOW() - INTERVAL '7 days') as total_sos,
        COUNT(*) FILTER (WHERE severity = 'vigilance' AND created_at > NOW() - INTERVAL '7 days') as total_vigilance
      FROM incidents
    `);
    const activeRes = await pool.query(`
      SELECT COUNT(*)::int as count FROM users WHERE last_seen_at > NOW() - INTERVAL '24 hours'
    `);
    const safeZonesRes = await pool.query(`
      SELECT COUNT(*)::int as count FROM (
        SELECT zone_name FROM incidents
        WHERE status = 'verified' AND created_at > NOW() - INTERVAL '30 days'
        GROUP BY zone_name HAVING COUNT(*) < 3
      ) safe
    `);
    const byDayRes = await pool.query(`
      SELECT
        TO_CHAR(created_at, 'Dy') as day,
        COUNT(*)::int as count
      FROM incidents
      WHERE created_at > NOW() - INTERVAL '7 days'
      GROUP BY day ORDER BY MIN(created_at)
    `);
    const riskRes = await pool.query(`
      SELECT
        CASE
          WHEN EXTRACT(HOUR FROM created_at) BETWEEN 6 AND 8 THEN '06h – 08h'
          WHEN EXTRACT(HOUR FROM created_at) BETWEEN 12 AND 14 THEN '12h – 14h'
          WHEN EXTRACT(HOUR FROM created_at) BETWEEN 18 AND 20 THEN '18h – 20h'
          WHEN EXTRACT(HOUR FROM created_at) BETWEEN 20 AND 22 THEN '20h – 22h'
          ELSE 'Autre'
        END as label,
        ROUND(COUNT(*) * 100.0 / NULLIF(SUM(COUNT(*)) OVER(), 0))::int as level
      FROM incidents
      WHERE created_at > NOW() - INTERVAL '7 days'
      GROUP BY label
    `);

    const days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    const dayLabels = { Mon: "Lun", Tue: "Mar", Wed: "Mer", Thu: "Jeu", Fri: "Ven", Sat: "Sam", Sun: "Dim" };
    const byDayMap = {};
    for (const r of byDayRes.rows) byDayMap[r.day] = r.count;
    const incidents_by_day = days.map((d) => ({ day: dayLabels[d] || d, count: byDayMap[d] || 0 }));

    return res.json({
      total_incidents: parseInt(totalRes.rows[0].total_incidents) || 0,
      total_sos: parseInt(totalRes.rows[0].total_sos) || 0,
      active_users: parseInt(activeRes.rows[0].count) || 0,
      safe_zones: parseInt(safeZonesRes.rows[0].count) || 0,
      incidents_by_day,
      risk_hours: riskRes.rows.map((r) => ({ label: r.label, level: r.level || 0 })),
    });
  } catch (err) {
    console.error("getStats error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const getHeatmap = async (req, res) => {
  const { days } = req.query;
  const period = parseInt(days) || 30;
  try {
    const zones = await pool.query(`
      SELECT
        zone_name,
        COUNT(*)::int as total,
        COUNT(*) FILTER (WHERE severity = 'alert') as alerts,
        COUNT(*) FILTER (WHERE severity = 'vigilance') as vigilance,
        COUNT(*) FILTER (WHERE severity = 'danger') as danger,
        ROUND(AVG(lat)::numeric, 4) as avg_lat,
        ROUND(AVG(lng)::numeric, 4) as avg_lng
      FROM incidents
      WHERE created_at > NOW() - INTERVAL '${period} days'
        AND zone_name IS NOT NULL
      GROUP BY zone_name
      ORDER BY total DESC
    `);
    const unzoned = await pool.query(`
      SELECT
        COUNT(*)::int as total,
        COUNT(*) FILTER (WHERE severity = 'alert') as alerts
      FROM incidents
      WHERE created_at > NOW() - INTERVAL '${period} days'
        AND (zone_name IS NULL OR zone_name = '')
    `);
    return res.json({
      zones: zones.rows,
      unzoned: unzoned.rows[0],
      period,
    });
  } catch (err) {
    console.error("getHeatmap error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

module.exports = { getIncidents, reportIncident, verifyIncident, getStats, getHeatmap };
