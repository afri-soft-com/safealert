const { pool } = require("../config/database");
const { generateApiKey } = require("../middleware/partnerAuth");

const VALID_ROLES = ["citizen", "leader", "agent", "platform_admin"];

const listUsers = async (req, res) => {
  const page = Math.max(parseInt(req.query.page) || 1, 1);
  const limit = Math.min(Math.max(parseInt(req.query.limit) || 20, 1), 100);
  const offset = (page - 1) * limit;

  try {
    const countRes = await pool.query("SELECT COUNT(*)::int AS total FROM users");
    const result = await pool.query(
      `SELECT id, phone, pseudo, role, sector_name, created_at, last_seen_at
       FROM users ORDER BY created_at DESC LIMIT $1 OFFSET $2`,
      [limit, offset]
    );
    return res.json({
      data: result.rows,
      page,
      limit,
      total: countRes.rows[0].total,
    });
  } catch (err) {
    console.error("listUsers error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const updateUserRole = async (req, res) => {
  const { id } = req.params;
  const { role } = req.body;
  if (!role || !VALID_ROLES.includes(role)) {
    return res.status(400).json({ error: "Rôle invalide" });
  }
  if (id === req.userId && role !== "platform_admin") {
    return res.status(400).json({ error: "Vous ne pouvez pas retirer votre propre rôle admin" });
  }

  try {
    const result = await pool.query(
      `UPDATE users SET role = $1, updated_at = NOW() WHERE id = $2
       RETURNING id, phone, pseudo, role, sector_name`,
      [role, id]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: "Utilisateur non trouvé" });
    return res.json(result.rows[0]);
  } catch (err) {
    console.error("updateUserRole error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const updateUserSector = async (req, res) => {
  const { id } = req.params;
  const { sector_name } = req.body;

  try {
    const value = sector_name === null || sector_name === "" ? null : String(sector_name).trim();
    const result = await pool.query(
      `UPDATE users SET sector_name = $1, updated_at = NOW() WHERE id = $2
       RETURNING id, phone, pseudo, role, sector_name`,
      [value, id]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: "Utilisateur non trouvé" });
    return res.json(result.rows[0]);
  } catch (err) {
    console.error("updateUserSector error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const listPartners = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, partner_name, api_key, is_active, rate_limit, created_at, expires_at
       FROM partner_api_keys ORDER BY created_at DESC`
    );
    return res.json({ data: result.rows });
  } catch (err) {
    console.error("listPartners error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const createPartner = async (req, res) => {
  const { partner_name, rate_limit } = req.body;
  if (!partner_name) return res.status(400).json({ error: "Nom du partenaire requis" });

  try {
    const apiKey = generateApiKey();
    const result = await pool.query(
      `INSERT INTO partner_api_keys (partner_name, api_key, rate_limit)
       VALUES ($1, $2, $3) RETURNING *`,
      [partner_name, apiKey, rate_limit || 1000]
    );
    return res.status(201).json({
      partner_id: result.rows[0].id,
      partner_name: result.rows[0].partner_name,
      api_key: result.rows[0].api_key,
      message: "Conservez cette clé — elle ne sera plus affichée",
    });
  } catch (err) {
    console.error("createPartner error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const revokePartner = async (req, res) => {
  const { id } = req.params;
  try {
    const result = await pool.query(
      `UPDATE partner_api_keys SET is_active = false WHERE id = $1 RETURNING id, partner_name, is_active`,
      [id]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: "Partenaire non trouvé" });
    return res.json({ message: "Clé révoquée", partner: result.rows[0] });
  } catch (err) {
    console.error("revokePartner error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

module.exports = {
  listUsers,
  updateUserRole,
  updateUserSector,
  listPartners,
  createPartner,
  revokePartner,
  VALID_ROLES,
};
