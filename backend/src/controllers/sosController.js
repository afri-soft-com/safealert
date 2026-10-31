const { pool } = require("../config/database");
const { sendAlert, sendCancelAlert } = require("../services/alert");
const {
  notifyUserGroupsOnSOS,
  notifyUserGroupsOnFalseAlarm,
} = require("../services/groupNotify");
const { invalidateActiveAlerts } = require("../config/redis");
const { resolveZoneName, resolvePlace } = require("../utils/incidentZone");
const { deliverEvent } = require("../services/partnerWebhooks");
const { notifyLeadersForSOS } = require("../services/sectorNotify");
const { findMatchingZones } = require("./trustZoneController");
const crypto = require("crypto");
const { phoneLookupVariants } = require("../utils/phone");
const { sendPushToUser } = require("../services/pushTargets");
const {
  sosEnabled,
  maintenanceMode,
  sosAudio,
  sosPublicShare,
  sosMediation,
  witnessEvidence,
} = require("../config/features");
const { getEntitlementsForUser } = require("../services/premiumEntitlements");

const PUBLIC_BASE =
  process.env.PUBLIC_APP_URL ||
  process.env.CORS_ORIGIN?.split(",")[0]?.trim() ||
  "https://safealert-api.onrender.com";

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
    let zoneName = null;
    let zoneCity = null;
    try {
      const place = await resolvePlace(lat, lng);
      zoneName = place.zoneName;
      zoneCity = place.city;
    } catch (zErr) {
      console.warn("resolvePlace error:", zErr.message);
      try {
        zoneName = await resolveZoneName(lat, lng);
      } catch (_) {
        /* ignore */
      }
    }

    let priorityBoost = false;
    let wantMediation = false;
    try {
      const ents = await getEntitlementsForUser(req.userId);
      priorityBoost = !!ents.sos_priority;
      wantMediation =
        sosMediation() &&
        (!!ents.sos_mediation || !!ents.sos_priority) &&
        req.body.request_mediation !== false;
    } catch (entErr) {
      console.warn("getEntitlementsForUser error:", entErr.message);
    }

    const shareToken = sosPublicShare() ? crypto.randomBytes(12).toString("hex") : null;
    const insertFull = async () =>
      pool.query(
        `INSERT INTO incidents (
           user_id, incident_type, lat, lng, location, description, severity, zone_name, zone_city,
           priority_boost, mediation_requested, mediation_status, share_token, share_expires_at
         )
         VALUES (
           $1, $2, $3, $4,
           ST_SetSRID(ST_MakePoint($5, $6), 4326),
           $7, 'alert', $8, $9,
           $10, $11, $12, $13,
           CASE WHEN $13::text IS NOT NULL THEN NOW() + INTERVAL '6 hours' ELSE NULL END
         )
         RETURNING *`,
        [
          req.userId,
          incident_type || "sos",
          lat,
          lng,
          lng,
          lat,
          description,
          zoneName,
          zoneCity,
          priorityBoost,
          wantMediation,
          wantMediation ? "requested" : null,
          shareToken,
        ]
      );

    const insertMinimal = async () =>
      pool.query(
        `INSERT INTO incidents (user_id, incident_type, lat, lng, location, description, severity, zone_name, zone_city)
         VALUES (
           $1, $2, $3, $4,
           ST_SetSRID(ST_MakePoint($5, $6), 4326),
           $7, 'alert', $8, $9
         )
         RETURNING *`,
        [req.userId, incident_type || "sos", lat, lng, lng, lat, description, zoneName, zoneCity]
      );

    let incident;
    try {
      incident = (await insertFull()).rows[0];
    } catch (insErr) {
      console.error("triggerSOS full insert error:", insErr.code || "", insErr.message);
      incident = (await insertMinimal()).rows[0];
    }

    // Optional evidence attached at trigger (SOS audio / photo) — never fail the SOS.
    if (witnessEvidence() && sosAudio() && req.body.consent_evidence === true && req.body.evidence) {
      try {
        const items = Array.isArray(req.body.evidence) ? req.body.evidence : [req.body.evidence];
        for (const item of items.slice(0, 3)) {
          const mediaType = item.media_type === "photo" ? "photo" : "audio";
          const key = item.data_url || item.storage_key;
          if (!key || String(key).length < 20) continue;
          await pool.query(
            `INSERT INTO incident_evidence (incident_id, user_id, media_type, storage_key, retention_until)
             VALUES ($1, $2, $3, $4, NOW() + INTERVAL '7 days')`,
            [incident.id, req.userId, mediaType, String(key).slice(0, 500000)]
          );
        }
      } catch (evErr) {
        console.error("SOS evidence attach error:", evErr.message);
      }
    }

    // Notifications are best-effort: the SOS row must still return 201.
    let notification = {
      contactsNotified: 0,
      contactsPush: 0,
      contactsSms: 0,
      nearbyNotified: 0,
      nearbyPush: 0,
      degraded: false,
    };
    try {
      notification = {
        ...notification,
        ...(await sendAlert(
          req.userId,
          lat,
          lng,
          incident_type || "sos",
          incident.zone_name,
          incident.id
        )),
      };
    } catch (alertErr) {
      console.error("sendAlert error:", alertErr.message);
      notification.degraded = true;
      notification.error = true;
    }

    try {
      const userRes = await pool.query("SELECT pseudo FROM users WHERE id = $1", [req.userId]);
      const groupNotification = await notifyUserGroupsOnSOS(
        req.userId,
        lat,
        lng,
        userRes.rows[0]?.pseudo || "Un membre",
        incident.zone_name,
        req.app.get("io")
      );
      notification.groupSos = groupNotification;
    } catch (groupErr) {
      console.error("notifyUserGroupsOnSOS error:", groupErr.message);
      notification.groupSos = {
        groupsNotified: 0,
        membersNotified: 0,
        alertsCreated: 0,
        otherMembers: 0,
        error: true,
      };
    }

    try {
      await invalidateActiveAlerts();
    } catch (cacheErr) {
      console.error("invalidateActiveAlerts error:", cacheErr.message);
    }

    try {
      notification.sectorLeaders = await notifyLeadersForSOS(incident);
    } catch (sectorErr) {
      console.error("notifyLeadersForSOS error:", sectorErr.message);
      notification.sectorLeaders = { leadersNotified: 0, error: true };
    }

    // Targeted alerts for trust zones containing this SOS
    try {
      const zones = await findMatchingZones(lat, lng);
      for (const z of zones) {
        if (z.user_id === req.userId) continue;
        const tzContacts = await pool.query(
          `SELECT contact_phone FROM trust_contacts WHERE user_id = $1`,
          [z.user_id]
        );
        for (const tc of tzContacts.rows) {
          const variants = phoneLookupVariants(tc.contact_phone);
          if (!variants.length) continue;
          const matched = await pool.query(
            `SELECT id FROM users WHERE phone = ANY($1::text[]) LIMIT 1`,
            [variants]
          );
          const uid = matched.rows[0]?.id;
          if (!uid || String(uid) === String(req.userId)) continue;
          await sendPushToUser(uid, {
            notification: {
              title: `📍 Alerte près de ${z.label}`,
              body: `SOS signalé dans votre zone ${z.zone_type}`,
            },
            data: {
              type: "trust_zone_alert",
              zoneId: String(z.id),
              zoneLabel: String(z.label || ""),
              incidentId: String(incident.id),
              userId: String(req.userId),
              lat: String(lat ?? ""),
              lng: String(lng ?? ""),
              zone_name: incident.zone_name ? String(incident.zone_name) : "",
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

    const shareUrl = shareToken
      ? `${PUBLIC_BASE.replace(/\/$/, "")}/s/${shareToken}`
      : null;

    return res.status(201).json({
      incident,
      notification,
      share_url: shareUrl,
      mediation_requested: !!wantMediation,
      sos_audio_enabled: sosAudio(),
    });
  } catch (err) {
    console.error("triggerSOS error:", err.code || "", err.message, err.stack);
    // Last-chance minimal insert (any failure above).
    try {
      const place = await resolvePlace(lat, lng).catch(() => ({
        zoneName: null,
        city: null,
      }));
      const result = await pool.query(
        `INSERT INTO incidents (user_id, incident_type, lat, lng, location, description, severity, zone_name, zone_city)
         VALUES (
           $1, $2, $3, $4,
           ST_SetSRID(ST_MakePoint($5, $6), 4326),
           $7, 'alert', $8, $9
         )
         RETURNING *`,
        [
          req.userId,
          incident_type || "sos",
          lat,
          lng,
          lng,
          lat,
          description,
          place.zoneName,
          place.city,
        ]
      );
      return res.status(201).json({
        incident: result.rows[0],
        notification: { degraded: true, error: true },
      });
    } catch (e2) {
      console.error("triggerSOS last-chance insert error:", e2.code || "", e2.message);
    }
    const hint =
      err.code === "57P01" || /terminat|connect|ECONN|timeout/i.test(String(err.message || ""))
        ? "Base de données temporairement indisponible. Réessayez dans quelques secondes."
        : "Erreur lors de l'envoi de l'alerte. Réessayez ou utilisez l'annuaire d'urgence.";
    return res.status(500).json({
      error: hint,
      code: typeof err.code === "string" ? err.code : undefined,
    });
  }
};

/** Attach evidence (audio/photo) to an active SOS owned by the user. */
const attachEvidence = async (req, res) => {
  if (!witnessEvidence() || !sosAudio()) {
    return res.status(503).json({ error: "Preuves SOS désactivées" });
  }
  if (req.body.consent_evidence !== true) {
    return res.status(400).json({ error: "Consentement requis" });
  }
  const items = Array.isArray(req.body.evidence) ? req.body.evidence : [req.body.evidence];
  if (!items.length || !items[0]) {
    return res.status(400).json({ error: "Preuve manquante" });
  }
  try {
    const owned = await pool.query(
      `SELECT id FROM incidents WHERE id = $1 AND user_id = $2 AND status = 'active'`,
      [req.params.id, req.userId]
    );
    if (owned.rows.length === 0) {
      return res.status(404).json({ error: "Alerte introuvable" });
    }
    const inserted = [];
    for (const item of items.slice(0, 3)) {
      const mediaType = item.media_type === "photo" ? "photo" : "audio";
      const key = item.data_url || item.storage_key;
      if (!key) continue;
      const r = await pool.query(
        `INSERT INTO incident_evidence (incident_id, user_id, media_type, storage_key, retention_until)
         VALUES ($1, $2, $3, $4, NOW() + INTERVAL '7 days') RETURNING id, media_type, created_at`,
        [req.params.id, req.userId, mediaType, String(key).slice(0, 500000)]
      );
      inserted.push(r.rows[0]);
    }
    return res.status(201).json({ evidence: inserted });
  } catch (err) {
    console.error("attachEvidence error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

/** Create or refresh public SOS live share link. */
const createSosShare = async (req, res) => {
  if (!sosPublicShare()) {
    return res.status(503).json({ error: "Partage public SOS désactivé" });
  }
  try {
    const token = crypto.randomBytes(12).toString("hex");
    const result = await pool.query(
      `UPDATE incidents SET
         share_token = $3,
         share_expires_at = NOW() + INTERVAL '6 hours'
       WHERE id = $1 AND user_id = $2 AND status = 'active'
       RETURNING id, share_token, share_expires_at`,
      [req.params.id, req.userId, token]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Alerte introuvable" });
    }
    const shareUrl = `${PUBLIC_BASE.replace(/\/$/, "")}/s/${token}`;
    return res.json({ ...result.rows[0], share_url: shareUrl });
  } catch (err) {
    console.error("createSosShare error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

/** Ops: update mediation status. */
const updateMediation = async (req, res) => {
  if (!sosMediation()) {
    return res.status(503).json({ error: "Médiation désactivée" });
  }
  const status = String(req.body.status || "").trim();
  if (!["requested", "in_progress", "closed"].includes(status)) {
    return res.status(400).json({ error: "Statut médiation invalide" });
  }
  try {
    const result = await pool.query(
      `UPDATE incidents SET mediation_status = $2, mediation_requested = true
       WHERE id = $1 RETURNING id, mediation_requested, mediation_status, status`,
      [req.params.id, status]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Incident introuvable" });
    }
    return res.json(result.rows[0]);
  } catch (err) {
    console.error("updateMediation error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
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

    const io = req.app.get("io");
    try {
      const userRes = await pool.query("SELECT pseudo FROM users WHERE id = $1", [req.userId]);
      notification.groupSos = await notifyUserGroupsOnFalseAlarm(
        req.userId,
        incident.lat,
        incident.lng,
        userRes.rows[0]?.pseudo || "Un membre",
        incident.zone_name,
        io
      );
    } catch (groupErr) {
      console.error("notifyUserGroupsOnFalseAlarm error:", groupErr.message);
      notification.groupSos = { error: true };
    }

    deliverEvent("cancel", {
      id: incident.id,
      resolution: "false_alarm",
      message: "Fausse alerte — alerte annulée par l'utilisateur",
    }).catch(() => {});

    if (io) {
      io.emit("sos_cancelled", {
        id: incident.id,
        user_id: req.userId,
        resolution: "false_alarm",
        message: "Fausse alerte",
      });
    }

    return res.json({
      message: "Fausse alerte — vos contacts et groupes ont été notifiés",
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

    const io = req.app.get("io");
    try {
      const userRes = await pool.query("SELECT pseudo FROM users WHERE id = $1", [req.userId]);
      notification.groupSos = await notifyUserGroupsOnFalseAlarm(
        req.userId,
        incident.lat,
        incident.lng,
        userRes.rows[0]?.pseudo || "Un membre",
        incident.zone_name,
        io
      );
    } catch (groupErr) {
      console.error("notifyUserGroupsOnFalseAlarm error:", groupErr.message);
      notification.groupSos = { error: true };
    }

    deliverEvent("cancel", {
      id: incident.id,
      resolution: "false_alarm",
      message: "Fausse alerte — alerte annulée par l'utilisateur",
    }).catch(() => {});

    if (io) {
      io.emit("sos_cancelled", {
        id: incident.id,
        user_id: req.userId,
        resolution: "false_alarm",
        message: "Fausse alerte",
      });
    }

    return res.json({
      message: "Fausse alerte — vos contacts et groupes ont été notifiés",
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

module.exports = {
  triggerSOS,
  cancelSOS,
  cancelLatestSOS,
  getMyAlerts,
  attachEvidence,
  createSosShare,
  updateMediation,
  CANCEL_WINDOW_MS,
};
