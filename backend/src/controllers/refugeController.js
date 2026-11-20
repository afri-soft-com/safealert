const { pool } = require("../config/database");

const CATEGORIES = ["hospital", "pharmacy", "fuel", "church", "shop", "other"];
/** Who may add or remove places: people who know the neighbourhood. */
const EDITOR_ROLES = new Set(["leader", "agent", "admin", "platform_admin"]);

const toNum = (v) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
};

/**
 * GET /api/refuges?lat=&lng=&radius_km=&category=
 * Nearest first when a position is given (haversine, km).
 */
const listRefuges = async (req, res) => {
  const lat = toNum(req.query.lat);
  const lng = toNum(req.query.lng);
  const radius = Math.min(Math.max(toNum(req.query.radius_km) ?? 10, 0.5), 50);
  const category = CATEGORIES.includes(String(req.query.category)) ? String(req.query.category) : null;
  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 50, 1), 200);
  const hasPos = lat != null && lng != null;

  const params = [];
  const add = (v) => {
    params.push(v);
    return `$${params.length}`;
  };
  const where = ["active = true"];
  if (category) where.push(`category = ${add(category)}`);

  let sql;
  if (hasPos) {
    const la = add(lat);
    const ln = add(lng);
    const distance = `6371 * acos(least(1.0, greatest(-1.0,
        cos(radians(${la})) * cos(radians(lat)) * cos(radians(lng) - radians(${ln}))
        + sin(radians(${la})) * sin(radians(lat)))))`;
    sql = `SELECT * FROM (
             SELECT id, name, category, lat, lng, address, phone, open_24h, created_at,
                    ${distance} AS distance_km
             FROM refuge_places WHERE ${where.join(" AND ")}
           ) r
           WHERE r.distance_km <= ${add(radius)}
           ORDER BY r.distance_km ASC LIMIT ${add(limit)}`;
  } else {
    sql = `SELECT id, name, category, lat, lng, address, phone, open_24h, created_at,
                  NULL::double precision AS distance_km
           FROM refuge_places WHERE ${where.join(" AND ")}
           ORDER BY name ASC LIMIT ${add(limit)}`;
  }

  try {
    const r = await pool.query(sql, params);
    return res.json({ refuges: r.rows });
  } catch (err) {
    console.error("listRefuges:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const createRefuge = async (req, res) => {
  if (!EDITOR_ROLES.has(req.userRole)) {
    return res.status(403).json({ error: "Réservé aux leaders et administrateurs." });
  }
  const b = req.body || {};
  const name = String(b.name || "").trim().slice(0, 120);
  const category = String(b.category || "");
  const lat = toNum(b.lat);
  const lng = toNum(b.lng);
  if (name.length < 2) return res.status(400).json({ error: "Nom requis (2 caractères min.)." });
  if (!CATEGORIES.includes(category)) {
    return res.status(400).json({ error: `Catégorie invalide (${CATEGORIES.join(", ")}).` });
  }
  if (lat == null || lng == null || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    return res.status(400).json({ error: "Position invalide." });
  }
  try {
    const r = await pool.query(
      `INSERT INTO refuge_places (name, category, lat, lng, address, phone, open_24h, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
      [
        name,
        category,
        lat,
        lng,
        b.address ? String(b.address).trim().slice(0, 200) : null,
        b.phone ? String(b.phone).trim().slice(0, 30) : null,
        b.open_24h === true,
        req.userId,
      ]
    );
    return res.status(201).json({ refuge: r.rows[0] });
  } catch (err) {
    console.error("createRefuge:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

/** Soft delete so a mistaken removal can be undone in the database. */
const deleteRefuge = async (req, res) => {
  if (!EDITOR_ROLES.has(req.userRole)) {
    return res.status(403).json({ error: "Réservé aux leaders et administrateurs." });
  }
  try {
    const r = await pool.query(
      `UPDATE refuge_places SET active = false WHERE id = $1 AND active = true RETURNING id`,
      [req.params.id]
    );
    if (r.rows.length === 0) return res.status(404).json({ error: "Lieu introuvable." });
    return res.json({ deleted: true });
  } catch (err) {
    console.error("deleteRefuge:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = { listRefuges, createRefuge, deleteRefuge, CATEGORIES };
