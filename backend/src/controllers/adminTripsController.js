const { pool } = require("../config/database");
const { writeAudit } = require("../services/audit");

const STATUSES = new Set(["active", "arrived", "alerted", "cancelled", "expired"]);
const TRIP_MODES = new Set(["destination", "patrol"]);
const TRANSPORT = new Set(["moto", "car", "walk", "bus", "other"]);
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const clientIp = (req) =>
  req.headers["x-forwarded-for"]?.toString().split(",")[0]?.trim() || req.ip;

function num(v, fallback = null) {
  if (v === undefined || v === null || v === "") return fallback;
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function clipLabel(v, max = 200) {
  const s = String(v || "").trim();
  return s ? s.slice(0, max) : null;
}

async function loadTrack(tripId, limit = 800) {
  const r = await pool.query(
    `SELECT lat, lng, recorded_at
       FROM safe_trip_track_points
      WHERE trip_id = $1
      ORDER BY recorded_at ASC
      LIMIT $2`,
    [tripId, limit]
  );
  return r.rows;
}

const listTrips = async (req, res) => {
  const page = Math.max(parseInt(req.query.page, 10) || 1, 1);
  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 20, 1), 100);
  const offset = (page - 1) * limit;
  const status = String(req.query.status || "").trim();
  const tripMode = String(req.query.trip_mode || "").trim();
  const q = String(req.query.q || "").trim();
  const userId = String(req.query.user_id || "").trim();

  try {
    const conditions = ["1=1"];
    const params = [];

    if (status && STATUSES.has(status)) {
      params.push(status);
      conditions.push(`t.status = $${params.length}`);
    }
    if (tripMode && TRIP_MODES.has(tripMode)) {
      params.push(tripMode);
      conditions.push(`t.trip_mode = $${params.length}`);
    }
    if (userId && UUID_RE.test(userId)) {
      params.push(userId);
      conditions.push(`t.user_id = $${params.length}`);
    }
    if (q) {
      params.push(`%${q}%`);
      conditions.push(
        `(t.dest_label ILIKE $${params.length}
          OR t.vehicle_plate ILIKE $${params.length}
          OR u.pseudo ILIKE $${params.length}
          OR u.phone ILIKE $${params.length}
          OR t.id::text ILIKE $${params.length})`
      );
    }

    const where = conditions.join(" AND ");
    const countRes = await pool.query(
      `SELECT COUNT(*)::int AS total
         FROM safe_trips t
         JOIN users u ON u.id = t.user_id
        WHERE ${where}`,
      params
    );

    params.push(limit, offset);
    const result = await pool.query(
      `SELECT t.id, t.user_id, t.status, t.trip_mode, t.dest_label,
              t.origin_lat, t.origin_lng, t.dest_lat, t.dest_lng,
              t.last_lat, t.last_lng, t.eta_at, t.created_at, t.arrived_at,
              t.transport_mode, t.vehicle_plate, t.vehicle_note,
              t.notify_on_delay, t.last_ping_at,
              u.pseudo AS traveler_pseudo, u.phone AS traveler_phone
         FROM safe_trips t
         JOIN users u ON u.id = t.user_id
        WHERE ${where}
        ORDER BY t.created_at DESC
        LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );

    return res.json({
      data: result.rows,
      page,
      limit,
      total: countRes.rows[0].total,
    });
  } catch (err) {
    console.error("admin listTrips error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const getTrip = async (req, res) => {
  const { id } = req.params;
  if (!UUID_RE.test(id)) {
    return res.status(400).json({ error: "Identifiant invalide" });
  }

  try {
    const result = await pool.query(
      `SELECT t.*,
              u.pseudo AS traveler_pseudo, u.phone AS traveler_phone
         FROM safe_trips t
         JOIN users u ON u.id = t.user_id
        WHERE t.id = $1`,
      [id]
    );
    if (!result.rows[0]) {
      return res.status(404).json({ error: "Trajet non trouvé" });
    }
    const trip = result.rows[0];
    const track = await loadTrack(trip.id);
    return res.json({ ...trip, track });
  } catch (err) {
    console.error("admin getTrip error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const createTrip = async (req, res) => {
  const body = req.body || {};
  const userId = String(body.user_id || "").trim();
  if (!UUID_RE.test(userId)) {
    return res.status(400).json({ error: "user_id invalide" });
  }

  const originLat = num(body.origin_lat);
  const originLng = num(body.origin_lng);
  const destLat = num(body.dest_lat, originLat);
  const destLng = num(body.dest_lng, originLng);
  if (originLat == null || originLng == null) {
    return res.status(400).json({ error: "origin_lat et origin_lng sont requis" });
  }
  if (destLat == null || destLng == null) {
    return res.status(400).json({ error: "dest_lat et dest_lng sont requis" });
  }

  const tripMode =
    String(body.trip_mode || "").toLowerCase() === "patrol" ? "patrol" : "destination";
  const status = STATUSES.has(String(body.status || ""))
    ? String(body.status)
    : "active";
  const minutes = Math.min(
    Math.max(parseInt(body.eta_minutes, 10) || (tripMode === "patrol" ? 120 : 60), 5),
    24 * 60
  );
  const destLabel =
    clipLabel(body.dest_label) ||
    (tripMode === "patrol" ? "Patrouille terrain" : "Destination");
  const transport = TRANSPORT.has(String(body.transport_mode || ""))
    ? String(body.transport_mode)
    : "moto";
  const plate = clipLabel(body.vehicle_plate, 32);
  const note = clipLabel(body.vehicle_note, 500);
  const notifyOnDelay =
    tripMode === "patrol" ? body.notify_on_delay === true : body.notify_on_delay !== false;

  try {
    const user = await pool.query(`SELECT id FROM users WHERE id = $1`, [userId]);
    if (!user.rows[0]) {
      return res.status(404).json({ error: "Utilisateur introuvable" });
    }

    if (status === "active") {
      const active = await pool.query(
        `SELECT id FROM safe_trips WHERE user_id = $1 AND status = 'active' LIMIT 1`,
        [userId]
      );
      if (active.rows[0]) {
        return res.status(409).json({
          error: "Cet utilisateur a déjà un trajet actif",
          active_trip_id: active.rows[0].id,
        });
      }
    }

    const result = await pool.query(
      `INSERT INTO safe_trips
         (user_id, origin_lat, origin_lng, dest_lat, dest_lng, dest_label,
          eta_at, last_lat, last_lng, last_ping_at, status,
          escort_contact_ids, notify_on_delay, transport_mode,
          vehicle_plate, vehicle_note, trip_mode,
          arrived_at)
       VALUES ($1,$2,$3,$4,$5,$6,
               NOW() + ($7::int * INTERVAL '1 minute'), $2,$3, NOW(), $8,
               '{}', $9, $10, $11, $12, $13,
               CASE WHEN $8 = 'arrived' THEN NOW() ELSE NULL END)
       RETURNING *`,
      [
        userId,
        originLat,
        originLng,
        destLat,
        destLng,
        destLabel,
        minutes,
        status,
        notifyOnDelay,
        transport,
        plate,
        note,
        tripMode,
      ]
    );

    const trip = result.rows[0];
    await writeAudit({
      actorId: req.userId,
      action: "admin.trip.create",
      entityType: "safe_trip",
      entityId: trip.id,
      metadata: { user_id: userId, status, trip_mode: tripMode },
      ip: clientIp(req),
    });

    return res.status(201).json(trip);
  } catch (err) {
    console.error("admin createTrip error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const updateTrip = async (req, res) => {
  const { id } = req.params;
  if (!UUID_RE.test(id)) {
    return res.status(400).json({ error: "Identifiant invalide" });
  }

  const body = req.body || {};
  const sets = [];
  const params = [];

  const push = (sql, value) => {
    params.push(value);
    sets.push(`${sql} = $${params.length}`);
  };

  if (body.status !== undefined) {
    const status = String(body.status);
    if (!STATUSES.has(status)) {
      return res.status(400).json({ error: "Statut invalide" });
    }
    push("status", status);
    if (status === "arrived") {
      sets.push("arrived_at = COALESCE(arrived_at, NOW())");
    }
  }
  if (body.trip_mode !== undefined) {
    const mode = String(body.trip_mode).toLowerCase();
    if (!TRIP_MODES.has(mode)) {
      return res.status(400).json({ error: "trip_mode invalide" });
    }
    push("trip_mode", mode);
  }
  if (body.dest_label !== undefined) push("dest_label", clipLabel(body.dest_label));
  if (body.origin_lat !== undefined) {
    const v = num(body.origin_lat);
    if (v == null) return res.status(400).json({ error: "origin_lat invalide" });
    push("origin_lat", v);
  }
  if (body.origin_lng !== undefined) {
    const v = num(body.origin_lng);
    if (v == null) return res.status(400).json({ error: "origin_lng invalide" });
    push("origin_lng", v);
  }
  if (body.dest_lat !== undefined) {
    const v = num(body.dest_lat);
    if (v == null) return res.status(400).json({ error: "dest_lat invalide" });
    push("dest_lat", v);
  }
  if (body.dest_lng !== undefined) {
    const v = num(body.dest_lng);
    if (v == null) return res.status(400).json({ error: "dest_lng invalide" });
    push("dest_lng", v);
  }
  if (body.last_lat !== undefined) {
    const v = num(body.last_lat);
    if (v == null) return res.status(400).json({ error: "last_lat invalide" });
    push("last_lat", v);
  }
  if (body.last_lng !== undefined) {
    const v = num(body.last_lng);
    if (v == null) return res.status(400).json({ error: "last_lng invalide" });
    push("last_lng", v);
  }
  if (body.eta_at !== undefined) {
    const d = new Date(body.eta_at);
    if (Number.isNaN(d.getTime())) {
      return res.status(400).json({ error: "eta_at invalide" });
    }
    push("eta_at", d.toISOString());
  }
  if (body.eta_minutes !== undefined) {
    const minutes = Math.min(Math.max(parseInt(body.eta_minutes, 10) || 60, 5), 24 * 60);
    params.push(minutes);
    sets.push(`eta_at = NOW() + ($${params.length}::int * INTERVAL '1 minute')`);
  }
  if (body.transport_mode !== undefined) {
    const mode = String(body.transport_mode);
    if (!TRANSPORT.has(mode)) {
      return res.status(400).json({ error: "transport_mode invalide" });
    }
    push("transport_mode", mode);
  }
  if (body.vehicle_plate !== undefined) {
    push("vehicle_plate", clipLabel(body.vehicle_plate, 32));
  }
  if (body.vehicle_note !== undefined) {
    push("vehicle_note", clipLabel(body.vehicle_note, 500));
  }
  if (body.notify_on_delay !== undefined) {
    push("notify_on_delay", Boolean(body.notify_on_delay));
  }

  if (sets.length === 0) {
    return res.status(400).json({ error: "Aucun champ à mettre à jour" });
  }

  try {
    params.push(id);
    const result = await pool.query(
      `UPDATE safe_trips SET ${sets.join(", ")}
        WHERE id = $${params.length}
        RETURNING *`,
      params
    );
    if (!result.rows[0]) {
      return res.status(404).json({ error: "Trajet non trouvé" });
    }

    await writeAudit({
      actorId: req.userId,
      action: "admin.trip.update",
      entityType: "safe_trip",
      entityId: id,
      metadata: { fields: Object.keys(body) },
      ip: clientIp(req),
    });

    return res.json(result.rows[0]);
  } catch (err) {
    console.error("admin updateTrip error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const deleteTrip = async (req, res) => {
  const { id } = req.params;
  if (!UUID_RE.test(id)) {
    return res.status(400).json({ error: "Identifiant invalide" });
  }

  try {
    const result = await pool.query(
      `DELETE FROM safe_trips WHERE id = $1 RETURNING id, user_id, status`,
      [id]
    );
    if (!result.rows[0]) {
      return res.status(404).json({ error: "Trajet non trouvé" });
    }

    await writeAudit({
      actorId: req.userId,
      action: "admin.trip.delete",
      entityType: "safe_trip",
      entityId: id,
      metadata: {
        user_id: result.rows[0].user_id,
        status: result.rows[0].status,
      },
      ip: clientIp(req),
    });

    return res.json({ message: "Trajet supprimé", id });
  } catch (err) {
    console.error("admin deleteTrip error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = {
  listTrips,
  getTrip,
  createTrip,
  updateTrip,
  deleteTrip,
  STATUSES,
};
