const { pool } = require("../config/database");
const { sendAlert, sendCancelAlert } = require("../services/alert");
const { notifyUserGroupsOnSOS } = require("../services/groupNotify");
const { invalidateActiveAlerts } = require("../config/redis");
const { resolveZoneName } = require("../utils/incidentZone");
const { deliverEvent } = require("../services/partnerWebhooks");
const { notifyLeadersForSOS } = require("../services/sectorNotify");
const { findMatchingZones } = require("./trustZoneController");
const { sendPush } = require("../config/firebase");
const { sosEnabled, maintenanceMode } = require("../config/features");
const { getEntitlementsForUser } = require("../services/premiumEntitlements");

const CANCEL_WINDOW_MS = 2 * 60 * 1000;

const assertWithinCancelWindow = (incident) => {
  const elapsed = Date.now() - new Date(incident.created_at).getTime();
  if (elapsed > CANCEL_WINDOW_MS) {
    return "Délai d'annulation dépassé (2 minutes maximum)";
  }
  return null;
};

const isNullIsland = (lat, lng) =>
  Math.abs(Number(lat)) < 0.0001 && Math.abs(Number(lng)) < 0.0001;

const triggerSOS = async (req, res) => {
  if (maintenanceMode() || !sosEnabled()) {
    return res.status(503).json({
      error:
        "Les alertes sont temporairement indisponibles. Contactez les numéros d'urgence locaux si besoin.",
      maintenance: true,
    });
  }

  let { lat, lng, incident_type, description } = req.body;
  lat = Number(lat);
  lng = Number(lng);

  // Prefer last-known server position over 0,0 / null island
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || isNullIsland(lat, lng)) {
    try {
      const last = await pool.query(
        `SELECT last_lat, last_lng FROM users WHERE id = $1`,
        [req.userId]
      );
      const la = last.rows[0]?.last_lat;
      const ln = last.rows[0]?.last_lng;
      if (la != null && ln != null && !isNullIsland(la, ln)) {
        lat = Number(la);
        lng = Number(ln);
      }
    } catch (_) {
      /* ignore */
    }
  }

  if (!Number.isFinite(lat) || !Number.isFinite(lng) || isNullIsland(lat, lng)) {
    return res.status(400).json({
      error:
        "Position GPS indisponible. Activez la localisation et réessayez, ou utilisez l'annuaire d'urgence.",
    });
  }

  try {
    const zoneName = await resolveZoneName(lat, lng);
    const ents = await getEntitlementsForUser(req.userId);
    const priorityBoost = !!ents.sos_priority;
    const result = await pool.query(
      `INSERT INTO incidents (user_id, incident_type, lat, lng, location, description, severity, zone_name, priority_boost)
       VALUES ($1, $2, $3, $4, ST_SetSRID(ST_MakePoint($5, $6), 4326), $7, 'alert', $8, $9)
       RETURNING *`,
      [req.userId, incident_type || "sos", lat, lng, lng, lat, description, zoneName, priorityBoost]
    );
    const incident = result.rows[0];

    const notification = await sendAlert(
      req.userId,
      lat,
      lng,
      incident_type || "sos",
      incident.zone_name
    );

    const userRes = await pool.query("SELECT pseudo FROM users WHERE id = $1", [req.userId]);
    const groupNotification = await notifyUserGroupsOnSOS(
      req.userId,
      lat,
      lng,
      userRes.rows[0]?.pseudo || "Un membre",
      incident.zone_name
    );
    notification.groupSos = groupNotification;

    await invalidateActiveAlerts();

    const sectorNotify = await notifyLeadersForSOS(incident);
    notification.sectorLeaders = sectorNotify;

    // Targeted alerts for trust zones containing this SOS
    try {
      const zones = await findMatchingZones(lat, lng);
      for (const z of zones) {
        if (z.user_id === req.userId) continue;
        const contacts = await pool.query(
          `SELECT u.id AS uid, u.fcm_token FROM trust_contacts tc
           LEFT JOIN users u ON tc.contact_phone = u.phone
           WHERE tc.user_id = $1 AND u.fcm_token IS NOT NULL`,
          [z.user_id]
        );
        for (const c of contacts.rows) {
          if (c.uid && String(c.uid) === String(req.userId)) continue;
          await sendPush(c.fcm_token, {
            notification: {
              title: `📍 Alerte près de ${z.label}`,
              body: `SOS signalé dans votre zone ${z.zone_type}`,
            },
            data: {
              type: "trust_zone_alert",
              zoneId: String(z.id),
              incidentId: String(incident.id),
              userId: String(req.userId),
            },
          });
        }
      }
    } catch (tzErr) {
      console.error("trust zone notify error:", tzErr.message);
    }

    deliverEvent("sos", {
      id: incident.id,
      lat: incident.lat,
      lng: incident.lng,
      incident_type: incident.incident_type,
      zone_name: incident.zone_name,
      created_at: incident.created_at,
    }).catch(() => {});

    const io = req.app.get("io");
    if (io) {
      io.emit("sos_alert", {
        id: incident.id,
        user_id: req.userId,
        lat: incident.lat,
        lng: incident.lng,
        zone_name: incident.zone_name,
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
    await pool.query(`DELETE FROM sos_live_status WHERE incident_id = $1`, [incident.id]);
    await invalidateActiveAlerts();

    deliverEvent("cancel", {
      id: incident.id,
      resolution: "false_alarm",
      message: "Fausse alerte — alerte annulée par l'utilisateur",
    }).catch(() => {});

    const io = req.app.get("io");
    if (io) {
      io.emit("sos_cancelled", {
        id: incident.id,
        user_id: req.userId,
        resolution: "false_alarm",
        message: "Fausse alerte",
      });
    }

    return res.json({
      message: "Fausse alerte — vos contacts ont été notifiés",
      resolution: "false_alarm",
      incident: result.rows[0],
      notification,
    });
  } catch (err) {
    console.error("cancelSOS error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
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
    await pool.query(`DELETE FROM sos_live_status WHERE incident_id = $1`, [incident.id]);
    await invalidateActiveAlerts();

    deliverEvent("cancel", {
      id: incident.id,
      resolution: "false_alarm",
      message: "Fausse alerte — alerte annulée par l'utilisateur",
    }).catch(() => {});

    const io = req.app.get("io");
    if (io) {
      io.emit("sos_cancelled", {
        id: incident.id,
        user_id: req.userId,
        resolution: "false_alarm",
        message: "Fausse alerte",
      });
    }

    return res.json({
      message: "Fausse alerte — vos contacts ont été notifiés",
      resolution: "false_alarm",
      incident: result.rows[0],
      notification,
    });
  } catch (err) {
    console.error("cancelLatestSOS error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
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
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = { triggerSOS, cancelSOS, cancelLatestSOS, getMyAlerts, CANCEL_WINDOW_MS };
