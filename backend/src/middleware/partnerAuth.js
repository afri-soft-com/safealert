const crypto = require("crypto");
const { pool } = require("../config/database");
const { enforcePartnerRateLimit } = require("./rateLimit");

const authenticatePartner = async (req, res, next) => {
  const apiKey = req.headers["x-api-key"];
  if (!apiKey) {
    return res.status(401).json({ error: "Clé API requise (header X-API-Key)" });
  }

  try {
    const result = await pool.query(
      `SELECT id, partner_name, rate_limit, expires_at FROM partner_api_keys
       WHERE api_key = $1 AND is_active = true`,
      [apiKey]
    );
    if (result.rows.length === 0) {
      return res.status(403).json({ error: "Clé API invalide ou désactivée" });
    }

    const partner = result.rows[0];
    if (partner.expires_at && new Date(partner.expires_at) < new Date()) {
      return res.status(403).json({ error: "Clé API expirée" });
    }

    req.partner = partner;
    req.partnerId = partner.id;
    return enforcePartnerRateLimit(req, res, next);
  } catch (err) {
    console.error("partnerAuth error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const generateApiKey = () => crypto.randomBytes(32).toString("hex");

module.exports = { authenticatePartner, generateApiKey };
