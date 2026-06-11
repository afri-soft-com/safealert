const { pool } = require("../config/database");
const crypto = require("crypto");

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

const getMyGroups = async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT g.id, g.name, g.description, g.zone_name, g.member_count, g.invite_code, g.created_at,
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
  const { name, description, zone_name } = req.body;
  if (!name) return res.status(400).json({ error: "Nom du groupe requis" });

  try {
    const inviteCode = crypto.randomBytes(4).toString("hex").toUpperCase();
    const group = await pool.query(
      `INSERT INTO neighborhood_groups (name, description, zone_name, created_by, invite_code)
       VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [name, description || null, zone_name || null, req.userId, inviteCode]
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

    const already = await pool.query(
      "SELECT id FROM group_members WHERE group_id = $1 AND user_id = $2",
      [groupId, req.userId]
    );
    if (already.rows.length > 0) return res.status(409).json({ error: "Déjà membre du groupe" });

    const pending = await pool.query(
      `SELECT id, status FROM group_join_requests
       WHERE group_id = $1 AND user_id = $2`,
      [groupId, req.userId]
    );
    if (pending.rows.length > 0) {
      const status = pending.rows[0].status;
      if (status === "pending") {
        return res.status(409).json({ error: "Demande déjà en attente" });
      }
      if (status === "rejected") {
        await pool.query(
          `UPDATE group_join_requests SET status = 'pending', created_at = NOW()
           WHERE id = $1`,
          [pending.rows[0].id]
        );
        return res.status(201).json({
          message: "Demande envoyée",
          status: "pending",
          group_id: groupId,
          group_name: group.rows[0].name,
        });
      }
    }

    await pool.query(
      `INSERT INTO group_join_requests (group_id, user_id, status)
       VALUES ($1, $2, 'pending')`,
      [groupId, req.userId]
    );
    return res.status(201).json({
      message: "Demande envoyée",
      status: "pending",
      group_id: groupId,
      group_name: group.rows[0].name,
    });
  } catch (err) {
    console.error("joinGroup error:", err);
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
    const result = await pool.query(`
      SELECT u.id, u.pseudo, u.phone, gm.role, gm.joined_at
      FROM group_members gm
      JOIN users u ON u.id = gm.user_id
      WHERE gm.group_id = $1
      ORDER BY gm.joined_at
    `, [id]);
    return res.json(result.rows);
  } catch (err) {
    console.error("getGroupMembers error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const discoverGroups = async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT g.id, g.name, g.description, g.zone_name, g.member_count,
             u.pseudo as created_by_name
      FROM neighborhood_groups g
      JOIN users u ON u.id = g.created_by
      WHERE g.id NOT IN (
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
  getJoinRequests,
  approveJoinRequest,
  rejectJoinRequest,
  leaveGroup,
  getGroupMembers,
  discoverGroups,
};
