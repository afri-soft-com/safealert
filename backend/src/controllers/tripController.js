const crypto = require("crypto");
const { pool } = require("../config/database");
const { sendPush } = require("../config/firebase");
const { sendSMS } = require("../services/sms");
const { sendAlert } = require("../services/alert");
const { safeTrip, escortMode, publicShare } = require("../config/features");
const { notifyTrustCircle } = require("./checkInController");
const { getEntitlementsForUser } = require("../services/premiumEntitlements");
const { estimateEtaMinutes, normalizeTransportMode } = require("../utils/geo");

const PUBLIC_BASE =
  process.env.PUBLIC_APP_URL ||
  process.env.API_PUBLIC_URL ||
  "https://safealert-api.onrender.com";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const assertTripEnabled = (res) => {
  if (!safeTrip()) {
    res.status(503).json({ error: "Trajet sécurisé désactivé" });
    return false;
  }
  return true;
};

const startTrip = async (req, res) => {
  if (!assertTripEnabled(res)) return;

  const {
    origin_lat, origin_lng, dest_lat, dest_lng, dest_label,
    eta_minutes, escort_contact_ids, notify_on_delay, transport_mode,
  } = req.body;

  const originLat = Number(origin_lat);
  const originLng = Number(origin_lng);
  const destLat = Number(dest_lat);
  const destLng = Number(dest_lng);

  if (
    !Number.isFinite(originLat) || !Number.isFinite(originLng) ||
    !Number.isFinite(destLat) || !Number.isFinite(destLng)
  ) {
    return res.status(400).json({ error: "Origine et destination requises" });
  }

  try {
    const ents = await getEntitlementsForUser(req.userId);
    if (ents.trips_per_week != null) {
      const weekCount = await pool.query(
        `SELECT COUNT(*)::int AS c FROM safe_trips
         WHERE user_id = $1 AND created_at > NOW() - INTERVAL '7 days'`,
        [req.userId]
      );
      if (weekCount.rows[0].c >= ents.trips_per_week) {
        return res.status(403).json({
          error: `Limite de trajets gratuits atteinte (${ents.trips_per_week}/semaine). Activez Premium pour illimité.`,
          code: "PREMIUM_REQUIRED",
        });
      }
    }

    const mode = normalizeTransportMode(transport_mode);
    const suggested = estimateEtaMinutes(originLat, originLng, destLat, destLng, mode);
    const requestedRaw = eta_minutes == null || eta_minutes === ""
      ? suggested
      : parseInt(eta_minutes, 10);
    const requested = Math.max(Number.isFinite(requestedRaw) ? requestedRaw : suggested, 5);
    if (requested > ents.trip_eta_max_minutes) {
      return res.status(403).json({
        error: `ETA max ${ents.trip_eta_max_minutes} min en gratuit. Premium jusqu'à ${12 * 60} min.`,
        code: "PREMIUM_REQUIRED",
        trip_eta_max_minutes: ents.trip_eta_max_minutes,
      });
    }
    const minutes = Math.min(requested, ents.trip_eta_max_minutes);
    const escorts = escortMode() && Array.isArray(escort_contact_ids)
      ? escort_contact_ids.map(String).filter((id) => UUID_RE.test(id))
      : [];

    const shareToken = publicShare() ? crypto.randomBytes(12).toString("hex") : null;
    // Token lives until ETA + 2h (or max 24h)
    const shareHours = Math.min(Math.max(Math.ceil(minutes / 60) + 2, 2), 24);

    const insertParams = [
      req.userId, originLat, originLng, destLat, destLng,
      dest_label || null, minutes, escorts, notify_on_delay !== false,
      shareToken, shareHours, mode,
    ];
    let result;
    try {
      result = await pool.query(
        `INSERT INTO safe_trips
           (user_id, origin_lat, origin_lng, dest_lat, dest_lng, dest_label,
            eta_at, last_lat, last_lng, last_ping_at, escort_contact_ids, notify_on_delay,
            share_token, share_expires_at, transport_mode)
         VALUES ($1,$2,$3,$4,$5,$6, NOW() + ($7 * INTERVAL '1 minute'), $2,$3, NOW(), $8, $9,
                 $10, CASE WHEN $10::text IS NOT NULL THEN NOW() + ($11 * INTERVAL '1 hour') ELSE NULL END,
                 $12)
         RETURNING *`,
        insertParams
      );
    } catch (insertErr) {
      if (insertErr.code !== "42703") throw insertErr;
      result = await pool.query(
        `INSERT INTO safe_trips
           (user_id, origin_lat, origin_lng, dest_lat, dest_lng, dest_label,
            eta_at, last_lat, last_lng, last_ping_at, escort_contact_ids, notify_on_delay,
            share_token, share_expires_at)
         VALUES ($1,$2,$3,$4,$5,$6, NOW() + ($7 * INTERVAL '1 minute'), $2,$3, NOW(), $8, $9,
                 $10, CASE WHEN $10::text IS NOT NULL THEN NOW() + ($11 * INTERVAL '1 hour') ELSE NULL END)
         RETURNING *`,
        insertParams.slice(0, 11)
      );
    }
    const trip = result.rows[0];
    const shareUrl = shareToken
      ? `${PUBLIC_BASE.replace(/\/$/, "")}/t/${shareToken}`
      : null;

    try {
      await notifyTrustCircle(
        req.userId,
        "🛣️ Trajet SafeAlert",
        `{pseudo} partage un trajet vers ${dest_label || "sa destination"} (ETA ${minutes} min).`,
        "safe_trip_started",
        `🛣️ SafeAlert — {pseudo} a démarré un trajet sécurisé (ETA ${minutes} min).`
      );
    } catch (notifyErr) {
      console.error("startTrip notify skipped:", notifyErr.message);
    }

    const io = req.app.get("io");
    if (io) {
      io.emit("trip_started", { trip_id: trip.id, user_id: req.userId });
      for (const cid of escorts) {
        io.to(`user:${cid}`).emit("escort_trip", { trip });
      }
    }

    return res.status(201).json({
      trip,
      share_url: shareUrl,
      share_text: shareUrl
        ? `Suivez mon trajet SafeAlert (lecture seule) : ${shareUrl}`
        : null,
    });
  } catch (err) {
    console.error("startTrip error:", err);
    if (err.code === "22P02") {
      return res.status(400).json({ error: "Contact d'escorte invalide." });
    }
    if (err.code === "42703") {
      return res.status(500).json({
        error: "Base trajets incomplète — relancez les migrations serveur.",
      });
    }
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const pingTrip = async (req, res) => {
  if (!assertTripEnabled(res)) return;
  const { id } = req.params;
  const { lat, lng } = req.body;
  if (lat == null || lng == null) {
    return res.status(400).json({ error: "Position requise" });
  }

  try {
    const existing = await pool.query(
      `SELECT * FROM safe_trips WHERE id = $1 AND user_id = $2 AND status = 'active'`,
      [id, req.userId]
    );
    if (existing.rows.length === 0) {
      return res.status(404).json({ error: "Trajet actif non trouvé" });
    }
    const trip = existing.rows[0];

    // Abnormal stop: moved < 30m since last ping and > 8 min elapsed
    let abnormal = trip.abnormal_stop_at;
    if (trip.last_lat != null && trip.last_lng != null) {
      const distRes = await pool.query(
        `SELECT ST_Distance(
           ST_SetSRID(ST_MakePoint($1,$2),4326)::geography,
           ST_SetSRID(ST_MakePoint($3,$4),4326)::geography
         ) AS meters`,
        [trip.last_lng, trip.last_lat, lng, lat]
      );
      const meters = distRes.rows[0].meters;
      const lastPing = trip.last_ping_at ? new Date(trip.last_ping_at).getTime() : 0;
      if (meters < 30 && Date.now() - lastPing > 8 * 60 * 1000 && !abnormal) {
        abnormal = new Date();
      } else if (meters >= 30) {
        abnormal = null;
      }
    }

    // Arrival: within 80m of destination
    const arrivalRes = await pool.query(
      `SELECT ST_Distance(
         ST_SetSRID(ST_MakePoint($1,$2),4326)::geography,
         ST_SetSRID(ST_MakePoint($3,$4),4326)::geography
       ) AS meters`,
      [trip.dest_lng, trip.dest_lat, lng, lat]
    );
    const nearDest = arrivalRes.rows[0].meters < 80;

    let status = "active";
    let arrivedAt = null;
    if (nearDest) {
      status = "arrived";
      arrivedAt = new Date();
    }

    const updated = await pool.query(
      `UPDATE safe_trips SET
         last_lat = $2, last_lng = $3, last_ping_at = NOW(),
         abnormal_stop_at = $4, status = $5, arrived_at = $6
       WHERE id = $1 RETURNING *`,
      [id, lat, lng, abnormal, status, arrivedAt]
    );

    const io = req.app.get("io");
    if (io) {
      const payload = {
        trip_id: id,
        user_id: req.userId,
        lat, lng,
        status,
      };
      io.emit("trip_ping", payload);
      for (const cid of trip.escort_contact_ids || []) {
        io.to(`user:${cid}`).emit("trip_ping", payload);
      }
    }

    if (status === "arrived") {
      await notifyTrustCircle(
        req.userId,
        "✅ Arrivée SafeAlert",
        "{pseudo} est arrivé(e) à destination.",
        "safe_trip_arrived",
        "✅ SafeAlert — {pseudo} est arrivé(e) à destination."
      );
    }

    return res.json({ trip: updated.rows[0] });
  } catch (err) {
    console.error("pingTrip error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const arriveTrip = async (req, res) => {
  if (!assertTripEnabled(res)) return;
  const { id } = req.params;
  try {
    const result = await pool.query(
      `UPDATE safe_trips SET status = 'arrived', arrived_at = NOW()
       WHERE id = $1 AND user_id = $2 AND status = 'active' RETURNING *`,
      [id, req.userId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Trajet actif non trouvé" });
    }
    await notifyTrustCircle(
      req.userId,
      "✅ Arrivée SafeAlert",
      "{pseudo} confirme son arrivée.",
      "safe_trip_arrived",
      "✅ SafeAlert — {pseudo} confirme son arrivée."
    );
    return res.json({ trip: result.rows[0] });
  } catch (err) {
    console.error("arriveTrip error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const cancelTrip = async (req, res) => {
  if (!assertTripEnabled(res)) return;
  const { id } = req.params;
  try {
    const result = await pool.query(
      `UPDATE safe_trips SET status = 'cancelled'
       WHERE id = $1 AND user_id = $2 AND status = 'active' RETURNING *`,
      [id, req.userId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Trajet actif non trouvé" });
    }
    return res.json({ trip: result.rows[0] });
  } catch (err) {
    console.error("cancelTrip error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const getActiveTrip = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT * FROM safe_trips WHERE user_id = $1 AND status = 'active'
       ORDER BY created_at DESC LIMIT 1`,
      [req.userId]
    );
    return res.json(result.rows[0] || {});
  } catch (err) {
    console.error("getActiveTrip error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const getTrip = async (req, res) => {
  try {
    const result = await pool.query(`SELECT * FROM safe_trips WHERE id = $1`, [req.params.id]);
    if (result.rows.length === 0) return res.status(404).json({ error: "Trajet non trouvé" });
    const trip = result.rows[0];
    const isOwner = String(trip.user_id) === String(req.userId);
    const escortIds = (trip.escort_contact_ids || []).map(String);
    const isEscort = escortMode() && escortIds.includes(String(req.userId));
    if (!isOwner && !isEscort) {
      // Trust contact by phone match
      const contact = await pool.query(
        `SELECT 1 FROM trust_contacts WHERE user_id = $1 AND contact_user_id = $2`,
        [trip.user_id, req.userId]
      );
      if (contact.rows.length === 0) {
        return res.status(403).json({ error: "Accès refusé" });
      }
    }
    return res.json(trip);
  } catch (err) {
    console.error("getTrip error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

/** Cron-friendly: overdue trips → auto SOS alert */
const processOverdueTrips = async () => {
  if (!safeTrip()) return { alerted: 0 };
  const overdue = await pool.query(
    `SELECT * FROM safe_trips
     WHERE status = 'active'
       AND notify_on_delay = true
       AND eta_at < NOW() - INTERVAL '5 minutes'`
  );
  let alerted = 0;
  for (const trip of overdue.rows) {
    await pool.query(`UPDATE safe_trips SET status = 'alerted' WHERE id = $1`, [trip.id]);
    const lat = trip.last_lat ?? trip.origin_lat;
    const lng = trip.last_lng ?? trip.origin_lng;
    try {
      await sendAlert(trip.user_id, lat, lng, "safe_trip_overdue");
      await pool.query(
        `INSERT INTO incidents (user_id, incident_type, lat, lng, location, description, severity, zone_name)
         VALUES ($1, 'safe_trip_overdue', $2, $3,
           ST_SetSRID(ST_MakePoint($4,$5),4326),
           'Non-arrivée au trajet sécurisé', 'alert', NULL)`,
        [trip.user_id, lat, lng, lng, lat]
      );
      alerted += 1;
    } catch (err) {
      console.error("overdue trip alert error:", err.message);
    }
  }

  // Abnormal stop > 15 min without movement
  const stuck = await pool.query(
    `SELECT * FROM safe_trips
     WHERE status = 'active'
       AND abnormal_stop_at IS NOT NULL
       AND abnormal_stop_at < NOW() - INTERVAL '15 minutes'`
  );
  for (const trip of stuck.rows) {
    await pool.query(`UPDATE safe_trips SET status = 'alerted' WHERE id = $1`, [trip.id]);
    const lat = trip.last_lat ?? trip.origin_lat;
    const lng = trip.last_lng ?? trip.origin_lng;
    try {
      await sendAlert(trip.user_id, lat, lng, "safe_trip_stop");
      alerted += 1;
    } catch (_) {}
  }

  return { alerted };
};

/** Create / refresh a public share link for an active trip */
const createShareLink = async (req, res) => {
  if (!assertTripEnabled(res)) return;
  if (!publicShare()) {
    return res.status(503).json({ error: "Partage public désactivé" });
  }
  try {
    const token = crypto.randomBytes(12).toString("hex");
    const hours = Math.min(Math.max(parseInt(req.body?.ttl_hours) || 4, 1), 24);
    const result = await pool.query(
      `UPDATE safe_trips SET
         share_token = $3,
         share_expires_at = NOW() + ($4 * INTERVAL '1 hour')
       WHERE id = $1 AND user_id = $2 AND status = 'active'
       RETURNING id, share_token, share_expires_at, dest_label, status`,
      [req.params.id, req.userId, token, hours]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Trajet actif non trouvé" });
    }
    const shareUrl = `${PUBLIC_BASE.replace(/\/$/, "")}/t/${token}`;
    return res.json({
      trip: result.rows[0],
      share_url: shareUrl,
      share_text: `Suivez mon trajet SafeAlert (lecture seule) : ${shareUrl}`,
    });
  } catch (err) {
    console.error("createShareLink error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

module.exports = {
  startTrip,
  pingTrip,
  arriveTrip,
  cancelTrip,
  getActiveTrip,
  getTrip,
  processOverdueTrips,
  createShareLink,
};
