const { pool } = require("../config/database");
const { getEntitlementsForUser } = require("../services/premiumEntitlements");

const getHistory = async (req, res) => {
  try {
    const ents = await getEntitlementsForUser(req.userId);
    const limit = Math.max(1, Math.min(ents.history_limit || 100, 200));
    const result = await pool.query(
      `SELECT * FROM incidents
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT $2`,
      [req.userId, limit]
    );
    return res.json({
      data: result.rows,
      history_limit: limit,
      tier: ents.tier,
    });
  } catch (err) {
    console.error("getHistory error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = { getHistory };
