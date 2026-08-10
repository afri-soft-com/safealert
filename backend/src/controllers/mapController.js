const { pool } = require("../config/database");
const { cacheGet, cacheSet, invalidateActiveAlerts } = require("../config/redis");
const { resolveZoneName } = require("../utils/incidentZone");
const { deliverEvent } = require("../services/partnerWebhooks");
const { witnessEvidence, reliabilityScore } = require("../config/features");

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
             COALESCE(i.reliability_score, 50) as reliability_score,
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
  const { lat, lng, incident_type, description, is_anonymous, evidence, consent_evidence } = req.body;
  if (!lat || !lng || !incident_type) {
    return res.status(400).json({ error: "Position et type d'incident requis" });
  }
  try {
    // Anti-spam: max 5 reports / hour
    const recent = await pool.query(
      `SELECT COUNT(*)::int AS c FROM incidents
       WHERE user_id = $1 AND created_at > NOW() - INTERVAL '1 hour'
         AND severity = 'vigilance'`,
      [req.userId]
    );
    if (recent.rows[0].c >= 5) {
      return res.status(429).json({ error: "Trop de signalements — réessayez plus tard" });
    }

    const userScore = await pool.query(
      `SELECT COALESCE(reliability_score, 50) AS score FROM users WHERE id = $1`,
      [req.userId]
    );
    const baseScore = reliabilityScore() ? userScore.rows[0].score : 50;

    const zoneName = await resolveZoneName(lat, lng);
    const result = await pool.query(
      `INSERT INTO incidents (user_id, incident_type, description, lat, lng, location, severity, is_anonymous, zone_name, reliability_score)
       VALUES ($1, $2, $3, $4, $5, ST_SetSRID(ST_MakePoint($6, $7), 4326), 'vigilance', $8, $9, $10)
       RETURNING *`,
      [req.userId, incident_type, description, lat, lng, lng, lat, is_anonymous || false, zoneName, baseScore]
    );
    const incident = result.rows[0];

    // Optional witness evidence (base64 data URL or storage key) — short retention 7 days
    if (witnessEvidence() && evidence && consent_evidence === true) {
      const items = Array.isArray(evidence) ? evidence : [evidence];
      for (const item of items.slice(0, 3)) {
        const mediaType = item.media_type === "audio" ? "audio" : "photo";
        const key = item.storage_key || item.data_url || null;
        if (!key || String(key).length > 2_000_000) continue;
        await pool.query(
          `INSERT INTO incident_evidence (incident_id, user_id, media_type, storage_key, retention_until)
           VALUES ($1, $2, $3, $4, NOW() + INTERVAL '7 days')`,
          [incident.id, req.userId, mediaType, String(key)]
        );
      }
    }

    await invalidateActiveAlerts();
    deliverEvent("incident", {
      id: incident.id,
      incident_type: incident.incident_type,
      lat: incident.lat,
      lng: incident.lng,
      zone_name: incident.zone_name,
      reliability_score: incident.reliability_score,
    }).catch(() => {});

    return res.status(201).json(incident);
  } catch (err) {
    console.error("reportIncident error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const verifyIncident = async (req, res) => {
  const { id } = req.params;
  try {
    const inc = await pool.query(
      "SELECT verified_by, status, severity, reliability_score, user_id FROM incidents WHERE id = $1",
      [id]
    );
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
    let newSeverity = inc.rows[0].severity || "vigilance";
    const newCount = (inc.rows[0].verified_by || 0) + 1;
    if (newCount >= 3) {
      newStatus = "verified";
      newSeverity = "danger";
    }

    // Reliability score: +8 per confirmation, cap 100; bump reporter score
    let relScore = null;
    if (reliabilityScore()) {
      relScore = Math.min(100, (inc.rows[0].reliability_score || 50) + 8);
      if (inc.rows[0].user_id) {
        await pool.query(
          `UPDATE users SET reliability_score = LEAST(100, COALESCE(reliability_score, 50) + 2)
           WHERE id = $1`,
          [inc.rows[0].user_id]
        );
      }
    }

    const result = await pool.query(
      `UPDATE incidents SET verified_by = $1, status = $2, severity = $3
         ${relScore != null ? ", reliability_score = $5" : ""}
       WHERE id = $4 RETURNING *`,
      relScore != null
        ? [newCount, newStatus, newSeverity, id, relScore]
        : [newCount, newStatus, newSeverity, id]
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
