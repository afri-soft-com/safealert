const { pool } = require("../config/database");
const crypto = require("crypto");
const { notifyGroupMembers } = require("../services/groupNotify");

const VALID_ALERT_TYPES = ["info", "help_needed", "offer_help", "danger"];
const DEFAULT_PAGE_LIMIT = 50;
const MAX_PAGE_LIMIT = 100;

const maskPhone = (phone) => {
  if (!phone || phone.length < 6) return "***";
  return `${phone.slice(0, 4)} *** ${phone.slice(-2)}`;
};

const isGroupAdmin = async (groupId, userId) => {
  const result = await pool.query(
    `SELECT 1 FROM neighborhood_groups g
     LEFT JOIN group_members gm ON gm.group_id = g.id AND gm.user_id = $2
     WHERE g.id = $1 AND (g.created_by = $2 OR gm.role = 'admin')
     LIMIT 1`,
    [groupId, userId]
  );
  return result.rows.length > 0;
};

const isGroupMember = async (groupId, userId) => {
  const result = await pool.query(
    "SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2 LIMIT 1",
    [groupId, userId]
  );
  return result.rows.length > 0;
};

const createJoinRequest = async (groupId, userId) => {
  const already = await pool.query(
    "SELECT id FROM group_members WHERE group_id = $1 AND user_id = $2",
    [groupId, userId]
  );
  if (already.rows.length > 0) {
    return { status: 409, body: { error: "Déjà membre du groupe" } };
  }

  const pending = await pool.query(
    `SELECT id, status FROM group_join_requests
     WHERE group_id = $1 AND user_id = $2`,
    [groupId, userId]
  );
  if (pending.rows.length > 0) {
    const status = pending.rows[0].status;
    if (status === "pending") {
      return { status: 409, body: { error: "Demande déjà en attente" } };
    }
    if (status === "rejected") {
      await pool.query(
        `UPDATE group_join_requests SET status = 'pending', created_at = NOW()
         WHERE id = $1`,
        [pending.rows[0].id]
      );
      return { status: 201, body: { message: "Demande envoyée", status: "pending", group_id: groupId } };
    }
  }

  await pool.query(
    `INSERT INTO group_join_requests (group_id, user_id, status)
     VALUES ($1, $2, 'pending')`,
    [groupId, userId]
  );
  return { status: 201, body: { message: "Demande envoyée", status: "pending", group_id: groupId } };
};

const getMyGroups = async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT g.id, g.name, g.description, g.zone_name, g.member_count, g.invite_code,
             g.is_public, g.created_at,
             gm.role as my_role,
             (SELECT COUNT(*)::int FROM group_join_requests r
              WHERE r.group_id = g.id AND r.status = 'pending') as pending_requests
      FROM neighborhood_groups g
      JOIN group_members gm ON gm.group_id = g.id
      WHERE gm.user_id = $1
      ORDER BY g.created_at DESC
    `, [req.userId]);
    return res.json(result.rows);
  } catch (err) {
    console.error("getMyGroups error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const createGroup = async (req, res) => {
  const { name, description, zone_name, is_public } = req.body;
  if (!name) return res.status(400).json({ error: "Nom du groupe requis" });

  try {
    const inviteCode = crypto.randomBytes(4).toString("hex").toUpperCase();
    const publicFlag = is_public !== false;
    const group = await pool.query(
      `INSERT INTO neighborhood_groups (name, description, zone_name, created_by, invite_code, is_public)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [name, description || null, zone_name || null, req.userId, inviteCode, publicFlag]
    );
    await pool.query(
      `INSERT INTO group_members (group_id, user_id, role) VALUES ($1, $2, 'admin')`,
      [group.rows[0].id, req.userId]
    );
    return res.status(201).json(group.rows[0]);
  } catch (err) {
    console.error("createGroup error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const joinGroup = async (req, res) => {
  const { invite_code } = req.body;
  if (!invite_code) return res.status(400).json({ error: "Code d'invitation requis" });

  try {
    const group = await pool.query(
      "SELECT id, name FROM neighborhood_groups WHERE invite_code = $1",
      [invite_code.toUpperCase()]
    );
    if (group.rows.length === 0) return res.status(404).json({ error: "Code invalide" });

    const groupId = group.rows[0].id;
    const result = await createJoinRequest(groupId, req.userId);
    if (result.status === 201) {
      result.body.group_name = group.rows[0].name;
    }
    return res.status(result.status).json(result.body);
  } catch (err) {
    console.error("joinGroup error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const joinGroupById = async (req, res) => {
  const { id } = req.params;
  try {
    const group = await pool.query(
      "SELECT id, name, is_public FROM neighborhood_groups WHERE id = $1",
      [id]
    );
    if (group.rows.length === 0) return res.status(404).json({ error: "Groupe introuvable" });
    if (!group.rows[0].is_public) {
      return res.status(403).json({ error: "Ce groupe n'accepte pas les demandes sans code" });
    }

    const result = await createJoinRequest(id, req.userId);
    if (result.status === 201) {
      result.body.group_name = group.rows[0].name;
    }
    return res.status(result.status).json(result.body);
  } catch (err) {
    console.error("joinGroupById error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const getJoinRequests = async (req, res) => {
  const { id } = req.params;
  try {
    if (!(await isGroupAdmin(id, req.userId))) {
      return res.status(403).json({ error: "Accès réservé aux administrateurs du groupe" });
    }
    const result = await pool.query(`
      SELECT r.id, r.group_id, r.user_id, r.status, r.created_at,
             u.pseudo, u.phone
      FROM group_join_requests r
      JOIN users u ON u.id = r.user_id
      WHERE r.group_id = $1 AND r.status = 'pending'
      ORDER BY r.created_at ASC
    `, [id]);
    return res.json(result.rows);
  } catch (err) {
    console.error("getJoinRequests error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const approveJoinRequest = async (req, res) => {
  const { id } = req.params;
  try {
    const request = await pool.query(
      `SELECT r.*, g.name as group_name FROM group_join_requests r
       JOIN neighborhood_groups g ON g.id = r.group_id
       WHERE r.id = $1 AND r.status = 'pending'`,
      [id]
    );
    if (request.rows.length === 0) {
      return res.status(404).json({ error: "Demande introuvable ou déjà traitée" });
    }
    const row = request.rows[0];
    if (!(await isGroupAdmin(row.group_id, req.userId))) {
      return res.status(403).json({ error: "Accès réservé aux administrateurs du groupe" });
    }

    const member = await pool.query(
      "SELECT id FROM group_members WHERE group_id = $1 AND user_id = $2",
      [row.group_id, row.user_id]
    );
    if (member.rows.length > 0) {
      await pool.query(
        "UPDATE group_join_requests SET status = 'approved' WHERE id = $1",
        [id]
      );
      return res.json({ message: "Utilisateur déjà membre", status: "approved" });
    }

    await pool.query("BEGIN");
    try {
      await pool.query(
        "INSERT INTO group_members (group_id, user_id) VALUES ($1, $2)",
        [row.group_id, row.user_id]
      );
      await pool.query(
        "UPDATE neighborhood_groups SET member_count = member_count + 1 WHERE id = $1",
        [row.group_id]
      );
      await pool.query(
        "UPDATE group_join_requests SET status = 'approved' WHERE id = $1",
        [id]
      );
      await pool.query("COMMIT");
    } catch (txErr) {
      await pool.query("ROLLBACK");
      throw txErr;
    }

    return res.json({ message: "Demande approuvée", status: "approved", group_id: row.group_id });
  } catch (err) {
    console.error("approveJoinRequest error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const rejectJoinRequest = async (req, res) => {
  const { id } = req.params;
  try {
    const request = await pool.query(
      "SELECT * FROM group_join_requests WHERE id = $1 AND status = 'pending'",
      [id]
    );
    if (request.rows.length === 0) {
      return res.status(404).json({ error: "Demande introuvable ou déjà traitée" });
    }
    const row = request.rows[0];
    if (!(await isGroupAdmin(row.group_id, req.userId))) {
      return res.status(403).json({ error: "Accès réservé aux administrateurs du groupe" });
    }

    await pool.query(
      "UPDATE group_join_requests SET status = 'rejected' WHERE id = $1",
      [id]
    );
    return res.json({ message: "Demande refusée", status: "rejected" });
  } catch (err) {
    console.error("rejectJoinRequest error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const leaveGroup = async (req, res) => {
  const { id } = req.params;
  try {
    await pool.query(
      "DELETE FROM group_members WHERE group_id = $1 AND user_id = $2",
      [id, req.userId]
    );
    await pool.query(
      "UPDATE neighborhood_groups SET member_count = GREATEST(member_count - 1, 0) WHERE id = $1",
      [id]
    );
    return res.json({ message: "Quitté le groupe" });
  } catch (err) {
    console.error("leaveGroup error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const getGroupMembers = async (req, res) => {
  const { id } = req.params;
  try {
    if (!(await isGroupMember(id, req.userId))) {
      return res.status(403).json({ error: "Accès réservé aux membres du groupe" });
    }
    const admin = await isGroupAdmin(id, req.userId);
    const result = await pool.query(`
      SELECT u.id, u.pseudo, u.phone, gm.role, gm.joined_at
      FROM group_members gm
      JOIN users u ON u.id = gm.user_id
      WHERE gm.group_id = $1
      ORDER BY gm.joined_at
    `, [id]);
    const rows = result.rows.map((row) => ({
      ...row,
      phone: admin ? row.phone : maskPhone(row.phone),
    }));
    return res.json(rows);
  } catch (err) {
    console.error("getGroupMembers error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const getGroupMessages = async (req, res) => {
  const { id } = req.params;
  const limit = Math.min(parseInt(req.query.limit, 10) || DEFAULT_PAGE_LIMIT, MAX_PAGE_LIMIT);
  const before = req.query.before || null;

  try {
    if (!(await isGroupMember(id, req.userId))) {
      return res.status(403).json({ error: "Accès réservé aux membres du groupe" });
    }

    const params = [id];
    let beforeClause = "";
    if (before) {
      beforeClause = "AND m.created_at < $2";
      params.push(before);
    }
    params.push(limit);

    const result = await pool.query(
      `SELECT m.id, m.group_id, m.user_id, m.content, m.created_at,
              u.pseudo as author_pseudo
       FROM group_messages m
       JOIN users u ON u.id = m.user_id
       WHERE m.group_id = $1 ${beforeClause}
       ORDER BY m.created_at DESC
       LIMIT $${params.length}`,
      params
    );

    return res.json({
      messages: result.rows.reverse(),
      has_more: result.rows.length === limit,
    });
  } catch (err) {
    console.error("getGroupMessages error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const postGroupMessage = async (req, res) => {
  const { id } = req.params;
  const { content } = req.body;
  if (!content || !String(content).trim()) {
    return res.status(400).json({ error: "Message requis" });
  }

  try {
    if (!(await isGroupMember(id, req.userId))) {
      return res.status(403).json({ error: "Accès réservé aux membres du groupe" });
    }

    const groupRes = await pool.query(
      "SELECT name FROM neighborhood_groups WHERE id = $1",
      [id]
    );
    const groupName = groupRes.rows[0]?.name || "Groupe";

    const userRes = await pool.query("SELECT pseudo FROM users WHERE id = $1", [req.userId]);
    const pseudo = userRes.rows[0]?.pseudo || "Membre";

    const result = await pool.query(
      `INSERT INTO group_messages (group_id, user_id, content)
       VALUES ($1, $2, $3)
       RETURNING id, group_id, user_id, content, created_at`,
      [id, req.userId, String(content).trim().slice(0, 2000)]
    );

    const message = {
      ...result.rows[0],
      author_pseudo: pseudo,
    };

    await notifyGroupMembers(
      id,
      req.userId,
      {
        title: `💬 ${groupName}`,
        body: `${pseudo}: ${String(content).trim().slice(0, 100)}`,
      },
      {
        type: "group_message",
        groupId: String(id),
        messageId: String(message.id),
      }
    );

    return res.status(201).json(message);
  } catch (err) {
    console.error("postGroupMessage error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const getGroupAlerts = async (req, res) => {
  const { id } = req.params;
  const limit = Math.min(parseInt(req.query.limit, 10) || DEFAULT_PAGE_LIMIT, MAX_PAGE_LIMIT);

  try {
    if (!(await isGroupMember(id, req.userId))) {
      return res.status(403).json({ error: "Accès réservé aux membres du groupe" });
    }

    const result = await pool.query(
      `SELECT a.id, a.group_id, a.author_id, a.type, a.title, a.body,
              a.lat, a.lng, a.created_at,
              u.pseudo as author_pseudo
       FROM group_alerts a
       JOIN users u ON u.id = a.author_id
       WHERE a.group_id = $1
       ORDER BY a.created_at DESC
       LIMIT $2`,
      [id, limit]
    );

    return res.json(result.rows);
  } catch (err) {
    console.error("getGroupAlerts error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const postGroupAlert = async (req, res) => {
  const { id } = req.params;
  const { type, title, body, lat, lng } = req.body;

  if (!type || !VALID_ALERT_TYPES.includes(type)) {
    return res.status(400).json({ error: "Type d'alerte invalide" });
  }
  if (!title || !String(title).trim()) {
    return res.status(400).json({ error: "Titre requis" });
  }

  try {
    if (!(await isGroupMember(id, req.userId))) {
      return res.status(403).json({ error: "Accès réservé aux membres du groupe" });
    }

    const groupRes = await pool.query(
      "SELECT name FROM neighborhood_groups WHERE id = $1",
      [id]
    );
    const groupName = groupRes.rows[0]?.name || "Groupe";

    const userRes = await pool.query("SELECT pseudo FROM users WHERE id = $1", [req.userId]);
    const pseudo = userRes.rows[0]?.pseudo || "Membre";

    const result = await pool.query(
      `INSERT INTO group_alerts (group_id, author_id, type, title, body, lat, lng)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING *`,
      [
        id,
        req.userId,
        type,
        String(title).trim().slice(0, 200),
        body ? String(body).trim().slice(0, 2000) : null,
        lat ?? null,
        lng ?? null,
      ]
    );

    const alert = result.rows[0];
    const typeLabels = {
      info: "ℹ️ Info",
      help_needed: "🆘 Aide demandée",
      offer_help: "🤝 Proposition d'aide",
      danger: "⚠️ Danger",
    };

    await notifyGroupMembers(
      id,
      req.userId,
      {
        title: `${typeLabels[type] || "Alerte"} — ${groupName}`,
        body: `${pseudo}: ${String(title).trim()}`,
      },
      {
        type: "group_alert",
        groupId: String(id),
        alertId: String(alert.id),
        alertType: type,
      }
    );

    return res.status(201).json({
      ...alert,
      author_pseudo: pseudo,
    });
  } catch (err) {
    console.error("postGroupAlert error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const discoverGroups = async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT g.id, g.name, g.description, g.zone_name, g.member_count, g.is_public,
             u.pseudo as created_by_name
      FROM neighborhood_groups g
      JOIN users u ON u.id = g.created_by
      WHERE g.is_public = true
        AND g.id NOT IN (
          SELECT group_id FROM group_members WHERE user_id = $1
        )
        AND g.id NOT IN (
          SELECT group_id FROM group_join_requests
          WHERE user_id = $1 AND status IN ('pending', 'approved')
        )
      ORDER BY g.member_count DESC LIMIT 20
    `, [req.userId]);
    return res.json(result.rows);
  } catch (err) {
    console.error("discoverGroups error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

module.exports = {
  getMyGroups,
  createGroup,
  joinGroup,
  joinGroupById,
  getJoinRequests,
  approveJoinRequest,
  rejectJoinRequest,
  leaveGroup,
  getGroupMembers,
  getGroupMessages,
  postGroupMessage,
  getGroupAlerts,
  postGroupAlert,
  discoverGroups,
};
