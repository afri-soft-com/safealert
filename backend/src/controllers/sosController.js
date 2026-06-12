const { pool } = require("../config/database");
const { sendAlert, sendCancelAlert } = require("../services/alert");
const { notifyUserGroupsOnSOS } = require("../services/groupNotify");
const { invalidateActiveAlerts } = require("../config/redis");
const { resolveZoneName } = require("../utils/incidentZone");

const CANCEL_WINDOW_MS = 2 * 60 * 1000;

const assertWithinCancelWindow = (incident) => {
  const elapsed = Date.now() - new Date(incident.created_at).getTime();
  if (elapsed > CANCEL_WINDOW_MS) {
    return "Délai d'annulation dépassé (2 minutes maximum)";
  }
  return null;
};

const triggerSOS = async (req, res) => {
  const { lat, lng, incident_type, description } = req.body;
  if (!lat || !lng) {
    return res.status(400).json({ error: "Position GPS requise" });
  }

  try {
    const zoneName = await resolveZoneName(lat, lng);
    const result = await pool.query(
      `INSERT INTO incidents (user_id, incident_type, lat, lng, location, description, severity, zone_name)
       VALUES ($1, $2, $3, $4, ST_SetSRID(ST_MakePoint($5, $6), 4326), $7, 'alert', $8)
       RETURNING *`,
      [req.userId, incident_type || "sos", lat, lng, lng, lat, description, zoneName]
    );
    const incident = result.rows[0];

    const notification = await sendAlert(req.userId, lat, lng, incident_type || "sos");

    const userRes = await pool.query("SELECT pseudo FROM users WHERE id = $1", [req.userId]);
    const groupNotification = await notifyUserGroupsOnSOS(
      req.userId,
      lat,
      lng,
      userRes.rows[0]?.pseudo || "Un membre"
    );
    notification.groupSos = groupNotification;

    await invalidateActiveAlerts();

    const io = req.app.get("io");
    if (io) {
      io.emit("sos_alert", {
        id: incident.id,
        lat: incident.lat,
        lng: incident.lng,
        incident_type: incident.incident_type,
        created_at: incident.created_at,
      });
    }

    return res.status(201).json({ incident, notification });
  } catch (err) {
    console.error("triggerSOS error:", err);
    return res.status(500).json({ error: "Erreur lors de l'envoi de l'alerte" });
  }
};

const cancelSOS = async (req, res) => {
  const { id } = req.params;
  try {
    const existing = await pool.query(
      `SELECT * FROM incidents WHERE id = $1 AND user_id = $2 AND status = 'active'`,
      [id, req.userId]
    );
    if (existing.rows.length === 0) {
      return res.status(404).json({ error: "Incident non trouvé ou déjà résolu" });
    }

    const windowError = assertWithinCancelWindow(existing.rows[0]);
    if (windowError) return res.status(403).json({ error: windowError });

    const incident = existing.rows[0];
    const result = await pool.query(
      `UPDATE incidents SET status = 'false_alarm', resolved_at = NOW()
       WHERE id = $1 AND user_id = $2 RETURNING *`,
      [id, req.userId]
    );

    const notification = await sendCancelAlert(req.userId, incident.lat, incident.lng);
    await invalidateActiveAlerts();

    const io = req.app.get("io");
    if (io) {
      io.emit("sos_cancelled", { id: incident.id, user_id: req.userId });
    }

    return res.json({ message: "Alerte annulée", incident: result.rows[0], notification });
  } catch (err) {
    console.error("cancelSOS error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const cancelLatestSOS = async (req, res) => {
  try {
    const existing = await pool.query(
      `SELECT * FROM incidents
       WHERE user_id = $1 AND status = 'active' AND severity = 'alert'
       ORDER BY created_at DESC LIMIT 1`,
      [req.userId]
    );
    if (existing.rows.length === 0) {
      return res.status(404).json({ error: "Aucune alerte active" });
    }

    const windowError = assertWithinCancelWindow(existing.rows[0]);
    if (windowError) return res.status(403).json({ error: windowError });

    const incident = existing.rows[0];
    const result = await pool.query(
      `UPDATE incidents SET status = 'false_alarm', resolved_at = NOW()
       WHERE id = $1 AND user_id = $2 RETURNING *`,
      [incident.id, req.userId]
    );

    const notification = await sendCancelAlert(req.userId, incident.lat, incident.lng);
    await invalidateActiveAlerts();

    const io = req.app.get("io");
    if (io) {
      io.emit("sos_cancelled", { id: incident.id, user_id: req.userId });
    }

    return res.json({ message: "Alerte annulée", incident: result.rows[0], notification });
  } catch (err) {
    console.error("cancelLatestSOS error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const getMyAlerts = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT * FROM incidents WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50`,
      [req.userId]
    );
    return res.json(result.rows);
  } catch (err) {
    console.error("getMyAlerts error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

module.exports = { triggerSOS, cancelSOS, cancelLatestSOS, getMyAlerts, CANCEL_WINDOW_MS };
