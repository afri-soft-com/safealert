const { pool } = require("../config/database");
const crypto = require("crypto");

const getMyGroups = async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT g.id, g.name, g.description, g.zone_name, g.member_count, g.invite_code, g.created_at,
             gm.role as my_role
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
      "SELECT id FROM neighborhood_groups WHERE invite_code = $1", [invite_code.toUpperCase()]
    );
    if (group.rows.length === 0) return res.status(404).json({ error: "Code invalide" });

    const already = await pool.query(
      "SELECT id FROM group_members WHERE group_id = $1 AND user_id = $2",
      [group.rows[0].id, req.userId]
    );
    if (already.rows.length > 0) return res.status(409).json({ error: "Déjà membre du groupe" });

    await pool.query(
      "INSERT INTO group_members (group_id, user_id) VALUES ($1, $2)",
      [group.rows[0].id, req.userId]
    );
    await pool.query(
      "UPDATE neighborhood_groups SET member_count = member_count + 1 WHERE id = $1",
      [group.rows[0].id]
    );
    return res.json({ message: "Rejoint avec succès", group_id: group.rows[0].id });
  } catch (err) {
    console.error("joinGroup error:", err);
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
      ORDER BY g.member_count DESC LIMIT 20
    `, [req.userId]);
    return res.json(result.rows);
  } catch (err) {
    console.error("discoverGroups error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

module.exports = { getMyGroups, createGroup, joinGroup, leaveGroup, getGroupMembers, discoverGroups };