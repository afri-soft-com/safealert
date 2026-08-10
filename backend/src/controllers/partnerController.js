const crypto = require("crypto");
const { pool } = require("../config/database");
const { generateApiKey } = require("../middleware/partnerAuth");

const registerPartner = async (req, res) => {
  const { partner_name, webhook_url, webhook_events } = req.body;
  if (!partner_name) return res.status(400).json({ error: "Nom du partenaire requis" });

  try {
    const apiKey = generateApiKey();
    const webhookSecret = crypto.randomBytes(24).toString("hex");
    const result = await pool.query(
      `INSERT INTO partner_api_keys (partner_name, api_key, webhook_url, webhook_secret, webhook_events)
       VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [
        partner_name,
        apiKey,
        webhook_url || null,
        webhookSecret,
        webhook_events || "sos,incident,cancel",
      ]
    );
    return res.status(201).json({
      partner_id: result.rows[0].id,
      partner_name: result.rows[0].partner_name,
      api_key: result.rows[0].api_key,
      webhook_secret: webhookSecret,
      webhook_url: result.rows[0].webhook_url,
      message: "Conservez cette clé — elle ne sera plus affichée",
    });
  } catch (err) {
    console.error("registerPartner error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

/** Partner portal: profile + webhook config (API key auth). */
const getPartnerMe = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, partner_name, is_active, rate_limit, webhook_url, webhook_events,
              created_at, expires_at
       FROM partner_api_keys WHERE id = $1`,
      [req.partnerId]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: "Partenaire non trouvé" });
    return res.json(result.rows[0]);
  } catch (err) {
    console.error("getPartnerMe error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const updateWebhook = async (req, res) => {
  const { webhook_url, webhook_events, rotate_secret } = req.body;
  try {
    let secretUpdate = "";
    const params = [req.partnerId];
    let i = 2;
    const sets = [];
    if (webhook_url !== undefined) {
      sets.push(`webhook_url = $${i++}`);
      params.push(webhook_url || null);
    }
    if (webhook_events !== undefined) {
      sets.push(`webhook_events = $${i++}`);
      params.push(webhook_events);
    }
    let newSecret = null;
    if (rotate_secret) {
      newSecret = crypto.randomBytes(24).toString("hex");
      sets.push(`webhook_secret = $${i++}`);
      params.push(newSecret);
    }
    if (sets.length === 0) {
      return res.status(400).json({ error: "Aucune modification" });
    }
    const result = await pool.query(
      `UPDATE partner_api_keys SET ${sets.join(", ")} WHERE id = $1
       RETURNING id, partner_name, webhook_url, webhook_events`,
      params
    );
    return res.json({
      partner: result.rows[0],
      ...(newSecret ? { webhook_secret: newSecret } : {}),
    });
  } catch (err) {
    console.error("updateWebhook error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const listWebhookDeliveries = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, event_type, status, response_code, attempts, created_at, delivered_at
       FROM partner_webhook_deliveries
       WHERE partner_id = $1
       ORDER BY created_at DESC LIMIT 50`,
      [req.partnerId]
    );
    return res.json(result.rows);
  } catch (err) {
    console.error("listWebhookDeliveries error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const getPublicStats = async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT
        COUNT(*) as total_incidents,
        COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '7 days') as weekly,
        COUNT(*) FILTER (WHERE status = 'verified') as verified,
        COUNT(DISTINCT zone_name) FILTER (WHERE zone_name IS NOT NULL) as zones_impacted,
        MIN(created_at) as first_incident,
        MAX(created_at) as last_incident
      FROM incidents
    `);
    return res.json(result.rows[0]);
  } catch (err) {
    console.error("getPublicStats error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const getPublicIncidents = async (req, res) => {
  const { limit, status, days } = req.query;
  try {
    const limitVal = Math.min(parseInt(limit) || 100, 1000);
    const statusFilter = status || "active,verified";
    const statuses = statusFilter.split(",").map(s => `'${s.trim()}'`).join(",");
    let whereClause = `WHERE i.status IN (${statuses})`;
    if (days) whereClause += ` AND i.created_at > NOW() - INTERVAL '${parseInt(days)} days'`;

    const result = await pool.query(`
      SELECT i.id, i.incident_type, i.description, i.lat, i.lng,
             i.severity, i.status, i.verified_by, i.zone_name, i.created_at, i.resolved_at
      FROM incidents i ${whereClause}
      ORDER BY i.created_at DESC LIMIT $1
    `, [limitVal]);
    return res.json(result.rows);
  } catch (err) {
    console.error("getPublicIncidents error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const getPublicHeatmap = async (req, res) => {
  const days = parseInt(req.query.days) || 30;
  try {
    const zones = await pool.query(`
      SELECT zone_name, COUNT(*)::int as count,
             ROUND(AVG(lat)::numeric, 4) as avg_lat,
             ROUND(AVG(lng)::numeric, 4) as avg_lng
      FROM incidents
      WHERE created_at > NOW() - INTERVAL '${days} days'
        AND zone_name IS NOT NULL
      GROUP BY zone_name ORDER BY count DESC
    `);
    return res.json({ zones: zones.rows, period: days, generated_at: new Date().toISOString() });
  } catch (err) {
    console.error("getPublicHeatmap error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

module.exports = {
  registerPartner,
  getPublicStats,
  getPublicIncidents,
  getPublicHeatmap,
  getPartnerMe,
  updateWebhook,
  listWebhookDeliveries,
};