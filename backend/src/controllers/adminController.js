const { pool } = require("../config/database");
const { generateApiKey } = require("../middleware/partnerAuth");
const { writeAudit } = require("../services/audit");

const VALID_ROLES = ["citizen", "leader", "agent", "platform_admin"];

const clientIp = (req) =>
  req.headers["x-forwarded-for"]?.toString().split(",")[0]?.trim() || req.ip;

const listUsers = async (req, res) => {
  const page = Math.max(parseInt(req.query.page) || 1, 1);
  const limit = Math.min(Math.max(parseInt(req.query.limit) || 20, 1), 100);
  const offset = (page - 1) * limit;
  const q = (req.query.q || req.query.search || "").toString().trim();

  try {
    const params = [];
    let where = "";
    if (q) {
      params.push(`%${q}%`);
      where = `WHERE phone ILIKE $1 OR pseudo ILIKE $1 OR COALESCE(sector_name, '') ILIKE $1`;
    }
    const countRes = await pool.query(
      `SELECT COUNT(*)::int AS total FROM users ${where}`,
      params
    );
    params.push(limit, offset);
    const limitIdx = params.length - 1;
    const offsetIdx = params.length;
    const result = await pool.query(
      `SELECT id, phone, pseudo, role, sector_name, created_at, last_seen_at
       FROM users ${where}
       ORDER BY created_at DESC
       LIMIT $${limitIdx} OFFSET $${offsetIdx}`,
      params
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
    await writeAudit({
      actorId: req.userId,
      action: "user.role.update",
      entityType: "user",
      entityId: id,
      metadata: { role },
      ip: clientIp(req),
    });
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
    await writeAudit({
      actorId: req.userId,
      action: "user.sector.update",
      entityType: "user",
      entityId: id,
      metadata: { sector_name: value },
      ip: clientIp(req),
    });
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
    await writeAudit({
      actorId: req.userId,
      action: "partner.create",
      entityType: "partner",
      entityId: result.rows[0].id,
      metadata: { partner_name },
      ip: clientIp(req),
    });
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
    await writeAudit({
      actorId: req.userId,
      action: "partner.revoke",
      entityType: "partner",
      entityId: id,
      ip: clientIp(req),
    });
    return res.json({ message: "Clé révoquée", partner: result.rows[0] });
  } catch (err) {
    console.error("revokePartner error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const getStats = async (req, res) => {
  try {
    const [usersRes, incidentsRes, activeRes, partnersRes, groupsRes] = await Promise.all([
      pool.query("SELECT COUNT(*)::int AS total FROM users"),
      pool.query("SELECT COUNT(*)::int AS total FROM incidents"),
      pool.query(
        `SELECT COUNT(*)::int AS total FROM incidents
         WHERE status IN ('active','verified','acknowledged','in_progress')`
      ),
      pool.query("SELECT COUNT(*)::int AS total FROM partner_api_keys WHERE is_active = true"),
      pool.query("SELECT COUNT(*)::int AS total FROM neighborhood_groups"),
    ]);
    return res.json({
      users: usersRes.rows[0].total,
      incidents: incidentsRes.rows[0].total,
      active_incidents: activeRes.rows[0].total,
      active_partners: partnersRes.rows[0].total,
      groups: groupsRes.rows[0].total,
    });
  } catch (err) {
    console.error("getStats error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const listEmergencyNumbers = async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT * FROM emergency_numbers ORDER BY country_code, service_type, service_name"
    );
    return res.json({ data: result.rows });
  } catch (err) {
    console.error("listEmergencyNumbers error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const createEmergencyNumber = async (req, res) => {
  const { country_code, service_name, service_type, phone_number, icon, is_offline_available } =
    req.body;
  if (!service_name || !service_type || !phone_number) {
    return res.status(400).json({ error: "Nom, type et numéro requis" });
  }
  try {
    const result = await pool.query(
      `INSERT INTO emergency_numbers (country_code, service_name, service_type, phone_number, icon, is_offline_available)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [
        (country_code || "CD").toUpperCase(),
        service_name.trim(),
        service_type.trim(),
        phone_number.trim(),
        icon || "📞",
        is_offline_available !== false,
      ]
    );
    await writeAudit({
      actorId: req.userId,
      action: "emergency.create",
      entityType: "emergency_number",
      entityId: result.rows[0].id,
      metadata: { service_name, phone_number },
      ip: clientIp(req),
    });
    return res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error("createEmergencyNumber error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const updateEmergencyNumber = async (req, res) => {
  const { id } = req.params;
  const { country_code, service_name, service_type, phone_number, icon, is_offline_available } =
    req.body;
  try {
    const result = await pool.query(
      `UPDATE emergency_numbers SET
        country_code = COALESCE($1, country_code),
        service_name = COALESCE($2, service_name),
        service_type = COALESCE($3, service_type),
        phone_number = COALESCE($4, phone_number),
        icon = COALESCE($5, icon),
        is_offline_available = COALESCE($6, is_offline_available)
       WHERE id = $7 RETURNING *`,
      [
        country_code ? String(country_code).toUpperCase() : null,
        service_name ? String(service_name).trim() : null,
        service_type ? String(service_type).trim() : null,
        phone_number ? String(phone_number).trim() : null,
        icon ?? null,
        is_offline_available ?? null,
        id,
      ]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: "Entrée non trouvée" });
    await writeAudit({
      actorId: req.userId,
      action: "emergency.update",
      entityType: "emergency_number",
      entityId: id,
      ip: clientIp(req),
    });
    return res.json(result.rows[0]);
  } catch (err) {
    console.error("updateEmergencyNumber error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const deleteEmergencyNumber = async (req, res) => {
  const { id } = req.params;
  try {
    const result = await pool.query("DELETE FROM emergency_numbers WHERE id = $1 RETURNING id", [
      id,
    ]);
    if (result.rows.length === 0) return res.status(404).json({ error: "Entrée non trouvée" });
    await writeAudit({
      actorId: req.userId,
      action: "emergency.delete",
      entityType: "emergency_number",
      entityId: id,
      ip: clientIp(req),
    });
    return res.json({ message: "Numéro supprimé", id: result.rows[0].id });
  } catch (err) {
    console.error("deleteEmergencyNumber error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const listIncidents = async (req, res) => {
  const page = Math.max(parseInt(req.query.page) || 1, 1);
  const limit = Math.min(Math.max(parseInt(req.query.limit) || 20, 1), 100);
  const offset = (page - 1) * limit;
  const { status, zone, from, to } = req.query;

  try {
    const conditions = ["1=1"];
    const params = [];
    let idx = 1;

    if (status) {
      conditions.push(`i.status = $${idx++}`);
      params.push(status);
    }
    if (zone) {
      conditions.push(`i.zone_name ILIKE $${idx++}`);
      params.push(`%${String(zone).trim()}%`);
    }
    if (from) {
      conditions.push(`i.created_at >= $${idx++}`);
      params.push(from);
    }
    if (to) {
      conditions.push(`i.created_at <= $${idx++}`);
      params.push(to);
    }

    const where = conditions.join(" AND ");
    const countRes = await pool.query(
      `SELECT COUNT(*)::int AS total FROM incidents i WHERE ${where}`,
      params
    );

    params.push(limit, offset);
    const result = await pool.query(
      `SELECT i.id, i.incident_type, i.description, i.lat, i.lng, i.zone_name,
              i.severity, i.status, i.verified_by, i.is_anonymous, i.created_at, i.resolved_at,
              CASE WHEN i.is_anonymous THEN 'Anonyme' ELSE u.pseudo END AS reporter,
              u.phone AS reporter_phone
       FROM incidents i
       JOIN users u ON i.user_id = u.id
       WHERE ${where}
       ORDER BY i.created_at DESC
       LIMIT $${idx++} OFFSET $${idx}`,
      params
    );

    return res.json({
      data: result.rows,
      page,
      limit,
      total: countRes.rows[0].total,
    });
  } catch (err) {
    console.error("listIncidents error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const listGroups = async (req, res) => {
  const page = Math.max(parseInt(req.query.page) || 1, 1);
  const limit = Math.min(Math.max(parseInt(req.query.limit) || 20, 1), 100);
  const offset = (page - 1) * limit;

  try {
    const countRes = await pool.query("SELECT COUNT(*)::int AS total FROM neighborhood_groups");
    const result = await pool.query(
      `SELECT g.id, g.name, g.description, g.zone_name, g.member_count, g.invite_code, g.created_at,
              u.pseudo AS creator_pseudo, u.phone AS creator_phone
       FROM neighborhood_groups g
       JOIN users u ON g.created_by = u.id
       ORDER BY g.created_at DESC
       LIMIT $1 OFFSET $2`,
      [limit, offset]
    );
    return res.json({
      data: result.rows,
      page,
      limit,
      total: countRes.rows[0].total,
    });
  } catch (err) {
    console.error("listGroups error:", err);
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
  getStats,
  listEmergencyNumbers,
  createEmergencyNumber,
  updateEmergencyNumber,
  deleteEmergencyNumber,
  listIncidents,
  listGroups,
  VALID_ROLES,
};
