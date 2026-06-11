const { pool } = require("../config/database");

const getHistory = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT * FROM incidents
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT 100`,
      [req.userId]
    );
    return res.json(result.rows);
  } catch (err) {
    console.error("getHistory error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

module.exports = { getHistory };
