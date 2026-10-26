const crypto = require("crypto");
const { pool } = require("../config/database");
const { writeAudit } = require("../services/audit");
const { normalizePhone, phoneLookupVariants } = require("../utils/phone");

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const clientIp = (req) =>
  req.headers["x-forwarded-for"]?.toString().split(",")[0]?.trim() || req.ip;

function newInviteCode() {
  return crypto.randomBytes(4).toString("hex").toUpperCase();
}

function clip(v, max) {
  const s = String(v || "").trim();
  return s ? s.slice(0, max) : null;
}

async function resolveUserId({ user_id, phone }) {
  if (user_id && UUID_RE.test(String(user_id))) {
    const r = await pool.query(
      `SELECT id, phone, pseudo, role FROM users WHERE id = $1 AND COALESCE(is_active, true) = true`,
      [user_id]
    );
    return r.rows[0] || null;
  }
  const raw = String(phone || "").trim();
  if (!raw) return null;
  const normalized = normalizePhone(raw) || raw;
  const variants = typeof phoneLookupVariants === "function"
    ? phoneLookupVariants(normalized)
    : [normalized, raw];
  const r = await pool.query(
    `SELECT id, phone, pseudo, role FROM users
      WHERE phone = ANY($1::text[]) AND COALESCE(is_active, true) = true
      LIMIT 1`,
    [variants]
  );
  return r.rows[0] || null;
}

async function recountMembers(groupId) {
  await pool.query(
    `UPDATE neighborhood_groups g
        SET member_count = (SELECT COUNT(*)::int FROM group_members m WHERE m.group_id = g.id)
      WHERE g.id = $1`,
    [groupId]
  );
}

async function ensureMemberAdmin(groupId, userId) {
  const existing = await pool.query(
    `SELECT id, role FROM group_members WHERE group_id = $1 AND user_id = $2`,
    [groupId, userId]
  );
  if (existing.rows[0]) {
    if (existing.rows[0].role !== "admin") {
      await pool.query(
        `UPDATE group_members SET role = 'admin' WHERE id = $1`,
        [existing.rows[0].id]
      );
    }
    return { created: false, promoted: existing.rows[0].role !== "admin" };
  }
  await pool.query(
    `INSERT INTO group_members (group_id, user_id, role) VALUES ($1, $2, 'admin')`,
    [groupId, userId]
  );
  await recountMembers(groupId);
  return { created: true, promoted: true };
}

const listGroups = async (req, res) => {
  const page = Math.max(parseInt(req.query.page, 10) || 1, 1);
  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 20, 1), 100);
  const offset = (page - 1) * limit;
  const q = String(req.query.q || "").trim();

  try {
    const params = [];
    let where = "1=1";
    if (q) {
      params.push(`%${q}%`);
      where = `(g.name ILIKE $1 OR g.zone_name ILIKE $1 OR g.invite_code ILIKE $1
        OR u.pseudo ILIKE $1 OR u.phone ILIKE $1)`;
    }

    const countRes = await pool.query(
      `SELECT COUNT(*)::int AS total
         FROM neighborhood_groups g
         JOIN users u ON u.id = g.created_by
        WHERE ${where}`,
      params
    );

    params.push(limit, offset);
    const result = await pool.query(
      `SELECT g.id, g.name, g.description, g.zone_name, g.member_count, g.invite_code,
              g.is_public, g.created_at, g.created_by,
              u.pseudo AS creator_pseudo, u.phone AS creator_phone,
              (SELECT COUNT(*)::int FROM group_members gm
                WHERE gm.group_id = g.id AND gm.role = 'admin') AS admin_count
         FROM neighborhood_groups g
         JOIN users u ON u.id = g.created_by
        WHERE ${where}
        ORDER BY g.created_at DESC
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
    console.error("admin listGroups error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const getGroup = async (req, res) => {
  const { id } = req.params;
  if (!UUID_RE.test(id)) {
    return res.status(400).json({ error: "Identifiant invalide" });
  }
  try {
    const group = await pool.query(
      `SELECT g.*, u.pseudo AS creator_pseudo, u.phone AS creator_phone
         FROM neighborhood_groups g
         JOIN users u ON u.id = g.created_by
        WHERE g.id = $1`,
      [id]
    );
    if (!group.rows[0]) {
      return res.status(404).json({ error: "Groupe introuvable" });
    }
    const members = await pool.query(
      `SELECT gm.id, gm.user_id, gm.role, gm.joined_at,
              u.pseudo, u.phone, u.role AS user_role
         FROM group_members gm
         JOIN users u ON u.id = gm.user_id
        WHERE gm.group_id = $1
        ORDER BY CASE WHEN gm.role = 'admin' THEN 0 ELSE 1 END, gm.joined_at ASC`,
      [id]
    );
    return res.json({
      ...group.rows[0],
      members: members.rows,
    });
  } catch (err) {
    console.error("admin getGroup error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const createGroup = async (req, res) => {
  const body = req.body || {};
  const name = clip(body.name, 100);
  if (!name || name.length < 2) {
    return res.status(400).json({ error: "Nom du groupe requis (2 caractères min.)" });
  }
  const description = clip(body.description, 2000);
  const zoneName = clip(body.zone_name, 100);
  const isPublic = body.is_public !== false;
  const adminIds = Array.isArray(body.admin_user_ids)
    ? body.admin_user_ids.map(String).filter((id) => UUID_RE.test(id))
    : [];
  const adminPhones = Array.isArray(body.admin_phones)
    ? body.admin_phones.map(String)
    : [];

  try {
    const inviteCode = newInviteCode();
    const group = await pool.query(
      `INSERT INTO neighborhood_groups
         (name, description, zone_name, created_by, invite_code, is_public, member_count)
       VALUES ($1, $2, $3, $4, $5, $6, 0)
       RETURNING *`,
      [name, description, zoneName, req.userId, inviteCode, isPublic]
    );
    const groupId = group.rows[0].id;

    // Creator (superadmin) is always a group admin
    await pool.query(
      `INSERT INTO group_members (group_id, user_id, role) VALUES ($1, $2, 'admin')`,
      [groupId, req.userId]
    );

    const addedAdmins = [];
    for (const uid of adminIds) {
      if (uid === req.userId) continue;
      const user = await resolveUserId({ user_id: uid });
      if (!user) continue;
      await ensureMemberAdmin(groupId, user.id);
      addedAdmins.push({ id: user.id, phone: user.phone, pseudo: user.pseudo });
    }
    for (const phone of adminPhones) {
      const user = await resolveUserId({ phone });
      if (!user || user.id === req.userId) continue;
      if (addedAdmins.some((a) => a.id === user.id)) continue;
      await ensureMemberAdmin(groupId, user.id);
      addedAdmins.push({ id: user.id, phone: user.phone, pseudo: user.pseudo });
    }

    await recountMembers(groupId);
    const refreshed = await pool.query(`SELECT * FROM neighborhood_groups WHERE id = $1`, [groupId]);

    await writeAudit({
      actorId: req.userId,
      action: "admin.group.create",
      entityType: "neighborhood_group",
      entityId: groupId,
      metadata: { name, admin_count: addedAdmins.length + 1 },
      ip: clientIp(req),
    });

    return res.status(201).json({
      ...refreshed.rows[0],
      admins_added: addedAdmins,
    });
  } catch (err) {
    console.error("admin createGroup error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const updateGroup = async (req, res) => {
  const { id } = req.params;
  if (!UUID_RE.test(id)) {
    return res.status(400).json({ error: "Identifiant invalide" });
  }
  const body = req.body || {};
  const sets = [];
  const params = [];

  if (body.name !== undefined) {
    const name = clip(body.name, 100);
    if (!name || name.length < 2) {
      return res.status(400).json({ error: "Nom invalide" });
    }
    params.push(name);
    sets.push(`name = $${params.length}`);
  }
  if (body.description !== undefined) {
    params.push(clip(body.description, 2000));
    sets.push(`description = $${params.length}`);
  }
  if (body.zone_name !== undefined) {
    params.push(clip(body.zone_name, 100));
    sets.push(`zone_name = $${params.length}`);
  }
  if (body.is_public !== undefined) {
    params.push(Boolean(body.is_public));
    sets.push(`is_public = $${params.length}`);
  }
  if (body.regenerate_invite === true) {
    params.push(newInviteCode());
    sets.push(`invite_code = $${params.length}`);
  }

  if (sets.length === 0) {
    return res.status(400).json({ error: "Aucun champ à mettre à jour" });
  }

  try {
    params.push(id);
    const result = await pool.query(
      `UPDATE neighborhood_groups SET ${sets.join(", ")}
        WHERE id = $${params.length}
        RETURNING *`,
      params
    );
    if (!result.rows[0]) {
      return res.status(404).json({ error: "Groupe introuvable" });
    }

    await writeAudit({
      actorId: req.userId,
      action: "admin.group.update",
      entityType: "neighborhood_group",
      entityId: id,
      metadata: { fields: Object.keys(body) },
      ip: clientIp(req),
    });

    return res.json(result.rows[0]);
  } catch (err) {
    console.error("admin updateGroup error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const deleteGroup = async (req, res) => {
  const { id } = req.params;
  if (!UUID_RE.test(id)) {
    return res.status(400).json({ error: "Identifiant invalide" });
  }
  try {
    const result = await pool.query(
      `DELETE FROM neighborhood_groups WHERE id = $1 RETURNING id, name`,
      [id]
    );
    if (!result.rows[0]) {
      return res.status(404).json({ error: "Groupe introuvable" });
    }
    await writeAudit({
      actorId: req.userId,
      action: "admin.group.delete",
      entityType: "neighborhood_group",
      entityId: id,
      metadata: { name: result.rows[0].name },
      ip: clientIp(req),
    });
    return res.json({ message: "Groupe supprimé", id });
  } catch (err) {
    console.error("admin deleteGroup error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const addGroupAdmin = async (req, res) => {
  const { id } = req.params;
  if (!UUID_RE.test(id)) {
    return res.status(400).json({ error: "Identifiant invalide" });
  }
  const body = req.body || {};
  try {
    const group = await pool.query(`SELECT id, name FROM neighborhood_groups WHERE id = $1`, [id]);
    if (!group.rows[0]) {
      return res.status(404).json({ error: "Groupe introuvable" });
    }

    const user = await resolveUserId({
      user_id: body.user_id,
      phone: body.phone,
    });
    if (!user) {
      return res.status(404).json({ error: "Utilisateur introuvable (UUID ou téléphone)." });
    }

    const result = await ensureMemberAdmin(id, user.id);

    await writeAudit({
      actorId: req.userId,
      action: "admin.group.add_admin",
      entityType: "neighborhood_group",
      entityId: id,
      metadata: { user_id: user.id, phone: user.phone, ...result },
      ip: clientIp(req),
    });

    return res.status(result.created ? 201 : 200).json({
      message: result.created
        ? "Administrateur ajouté au groupe"
        : result.promoted
          ? "Membre promu administrateur du groupe"
          : "Déjà administrateur du groupe",
      user: {
        id: user.id,
        phone: user.phone,
        pseudo: user.pseudo,
        role: "admin",
      },
      created: result.created,
      promoted: result.promoted,
    });
  } catch (err) {
    console.error("admin addGroupAdmin error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const setMemberRole = async (req, res) => {
  const { id, userId } = req.params;
  if (!UUID_RE.test(id) || !UUID_RE.test(userId)) {
    return res.status(400).json({ error: "Identifiant invalide" });
  }
  const role = String(req.body?.role || "").toLowerCase();
  if (role !== "admin" && role !== "member") {
    return res.status(400).json({ error: "Rôle invalide (admin|member)" });
  }

  try {
    if (role === "member") {
      const admins = await pool.query(
        `SELECT user_id FROM group_members WHERE group_id = $1 AND role = 'admin'`,
        [id]
      );
      if (admins.rows.length <= 1 && admins.rows[0]?.user_id === userId) {
        return res.status(400).json({
          error: "Impossible de retirer le dernier administrateur du groupe.",
        });
      }
    }

    const result = await pool.query(
      `UPDATE group_members SET role = $3
        WHERE group_id = $1 AND user_id = $2
        RETURNING id, group_id, user_id, role, joined_at`,
      [id, userId, role]
    );
    if (!result.rows[0]) {
      return res.status(404).json({ error: "Membre introuvable dans ce groupe" });
    }

    await writeAudit({
      actorId: req.userId,
      action: "admin.group.set_member_role",
      entityType: "neighborhood_group",
      entityId: id,
      metadata: { user_id: userId, role },
      ip: clientIp(req),
    });

    return res.json(result.rows[0]);
  } catch (err) {
    console.error("admin setMemberRole error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const removeMember = async (req, res) => {
  const { id, userId } = req.params;
  if (!UUID_RE.test(id) || !UUID_RE.test(userId)) {
    return res.status(400).json({ error: "Identifiant invalide" });
  }
  try {
    const member = await pool.query(
      `SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
      [id, userId]
    );
    if (!member.rows[0]) {
      return res.status(404).json({ error: "Membre introuvable" });
    }
    if (member.rows[0].role === "admin") {
      const admins = await pool.query(
        `SELECT COUNT(*)::int AS c FROM group_members WHERE group_id = $1 AND role = 'admin'`,
        [id]
      );
      if (admins.rows[0].c <= 1) {
        return res.status(400).json({
          error: "Impossible de retirer le dernier administrateur du groupe.",
        });
      }
    }

    await pool.query(
      `DELETE FROM group_members WHERE group_id = $1 AND user_id = $2`,
      [id, userId]
    );
    await recountMembers(id);

    await writeAudit({
      actorId: req.userId,
      action: "admin.group.remove_member",
      entityType: "neighborhood_group",
      entityId: id,
      metadata: { user_id: userId },
      ip: clientIp(req),
    });

    return res.json({ message: "Membre retiré", user_id: userId });
  } catch (err) {
    console.error("admin removeMember error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = {
  listGroups,
  getGroup,
  createGroup,
  updateGroup,
  deleteGroup,
  addGroupAdmin,
  setMemberRole,
  removeMember,
};
