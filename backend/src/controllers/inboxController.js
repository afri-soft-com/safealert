const { pool } = require("../config/database");

const listInbox = async (req, res) => {
  try {
    const rows = await pool.query(
      `SELECT id, type, title, body, payload, read_at, created_at
       FROM user_inbox
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT 100`,
      [req.userId]
    );
    const unread = rows.rows.filter((r) => !r.read_at).length;
    return res.json({ data: rows.rows, unread });
  } catch (err) {
    console.error("listInbox:", err.message);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const markRead = async (req, res) => {
  try {
    await pool.query(
      `UPDATE user_inbox SET read_at = NOW()
       WHERE id = $1 AND user_id = $2 AND read_at IS NULL`,
      [req.params.id, req.userId]
    );
    return res.json({ ok: true });
  } catch (err) {
    console.error("markRead:", err.message);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const markAllRead = async (req, res) => {
  try {
    await pool.query(
      `UPDATE user_inbox SET read_at = NOW()
       WHERE user_id = $1 AND read_at IS NULL`,
      [req.userId]
    );
    return res.json({ ok: true });
  } catch (err) {
    console.error("markAllRead:", err.message);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = { listInbox, markRead, markAllRead };
