const { pool } = require("../config/database");
const { trustZones } = require("../config/features");

const listZones = async (req, res) => {
  if (!trustZones()) return res.status(503).json({ error: "Zones de confiance désactivées" });
  try {
    const result = await pool.query(
      `SELECT * FROM trust_zones WHERE user_id = $1 ORDER BY created_at DESC`,
      [req.userId]
    );
    return res.json(result.rows);
  } catch (err) {
    console.error("listZones error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const createZone = async (req, res) => {
  if (!trustZones()) return res.status(503).json({ error: "Zones de confiance désactivées" });
  const { label, zone_type, lat, lng, radius_m, notify_contacts } = req.body;
  if (!label || !zone_type || lat == null || lng == null) {
    return res.status(400).json({ error: "label, zone_type et position requis" });
  }
  const allowed = ["home", "work", "school", "custom"];
  if (!allowed.includes(zone_type)) {
    return res.status(400).json({ error: "zone_type invalide" });
  }
  try {
    const count = await pool.query(
      `SELECT COUNT(*)::int AS c FROM trust_zones WHERE user_id = $1`,
      [req.userId]
    );
    if (count.rows[0].c >= 10) {
      return res.status(400).json({ error: "Maximum 10 zones de confiance" });
    }
    const result = await pool.query(
      `INSERT INTO trust_zones (user_id, label, zone_type, lat, lng, radius_m, notify_contacts)
       VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
      [
        req.userId, label, zone_type, lat, lng,
        Math.min(Math.max(parseInt(radius_m) || 200, 50), 5000),
        notify_contacts !== false,
      ]
    );
    return res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error("createZone error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const updateZone = async (req, res) => {
  if (!trustZones()) return res.status(503).json({ error: "Zones de confiance désactivées" });
  const { label, zone_type, lat, lng, radius_m, notify_contacts } = req.body || {};
  const allowed = ["home", "work", "school", "custom"];
  if (zone_type != null && !allowed.includes(zone_type)) {
    return res.status(400).json({ error: "zone_type invalide" });
  }
  try {
    const existing = await pool.query(
      `SELECT * FROM trust_zones WHERE id = $1 AND user_id = $2`,
      [req.params.id, req.userId]
    );
    if (existing.rows.length === 0) {
      return res.status(404).json({ error: "Zone non trouvée" });
    }
    const cur = existing.rows[0];
    const nextLabel =
      typeof label === "string" && label.trim() ? label.trim().slice(0, 120) : cur.label;
    const nextType = zone_type || cur.zone_type;
    const nextLat = lat != null ? Number(lat) : Number(cur.lat);
    const nextLng = lng != null ? Number(lng) : Number(cur.lng);
    const nextRadius = Math.min(
      Math.max(parseInt(radius_m != null ? radius_m : cur.radius_m, 10) || 200, 50),
      5000
    );
    const nextNotify =
      notify_contacts === undefined ? cur.notify_contacts !== false : notify_contacts !== false;

    if (!Number.isFinite(nextLat) || !Number.isFinite(nextLng)) {
      return res.status(400).json({ error: "Position invalide" });
    }

    const result = await pool.query(
      `UPDATE trust_zones
       SET label = $3, zone_type = $4, lat = $5, lng = $6, radius_m = $7, notify_contacts = $8
       WHERE id = $1 AND user_id = $2
       RETURNING *`,
      [
        req.params.id,
        req.userId,
        nextLabel,
        nextType,
        nextLat,
        nextLng,
        nextRadius,
        nextNotify,
      ]
    );
    return res.json(result.rows[0]);
  } catch (err) {
    console.error("updateZone error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const deleteZone = async (req, res) => {
  if (!trustZones()) return res.status(503).json({ error: "Zones de confiance désactivées" });
  try {
    const result = await pool.query(
      `DELETE FROM trust_zones WHERE id = $1 AND user_id = $2 RETURNING id`,
      [req.params.id, req.userId]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: "Zone non trouvée" });
    return res.json({ message: "Zone supprimée" });
  } catch (err) {
    console.error("deleteZone error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

/** Find trust zones containing a point (for targeted alerts). */
const findMatchingZones = async (lat, lng) => {
  if (!trustZones()) return [];
  // Do not filter notify_contacts here — owners must still get the alert;
  // contact fan-out is gated in sosController.
  const result = await pool.query(
    `SELECT tz.*, u.pseudo FROM trust_zones tz
     JOIN users u ON u.id = tz.user_id
     WHERE ST_DWithin(
         ST_SetSRID(ST_MakePoint(tz.lng, tz.lat), 4326)::geography,
         ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
         tz.radius_m
       )`,
    [lng, lat]
  );
  return result.rows;
};

module.exports = { listZones, createZone, updateZone, deleteZone, findMatchingZones };
