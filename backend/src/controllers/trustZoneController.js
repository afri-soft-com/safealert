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
    return res.status(500).json({ error: "Erreur serveur" });
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
    return res.status(500).json({ error: "Erreur serveur" });
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
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

/** Find trust zones containing a point (for targeted alerts). */
const findMatchingZones = async (lat, lng) => {
  if (!trustZones()) return [];
  const result = await pool.query(
    `SELECT tz.*, u.pseudo FROM trust_zones tz
     JOIN users u ON u.id = tz.user_id
     WHERE tz.notify_contacts = true
       AND ST_DWithin(
         ST_SetSRID(ST_MakePoint(tz.lng, tz.lat), 4326)::geography,
         ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
         tz.radius_m
       )`,
    [lng, lat]
  );
  return result.rows;
};

module.exports = { listZones, createZone, deleteZone, findMatchingZones };
