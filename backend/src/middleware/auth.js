const jwt = require("jsonwebtoken");
const { pool } = require("../config/database");

const authenticate = async (req, res, next) => {
  const header = req.headers.authorization;
  if (!header || !header.startsWith("Bearer ")) {
    return res.status(401).json({ error: "Authentification requise" });
  }

  const token = header.split(" ")[1];
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.userId = decoded.userId;
    req.userRole = decoded.role;
    req.sessionJti = decoded.jti || null;
    req.deviceId = decoded.deviceId || null;

    // Sessions with jti can be revoked (« Déconnecter partout »)
    if (decoded.jti) {
      try {
        const check = await pool.query(
          `SELECT id FROM user_devices
           WHERE user_id = $1 AND session_jti = $2 AND revoked_at IS NULL`,
          [decoded.userId, decoded.jti]
        );
        if (check.rows.length === 0) {
          return res.status(401).json({ error: "Session expirée. Reconnectez-vous." });
        }
      } catch (err) {
        // Table may not exist yet during rolling deploy — allow legacy tokens
        if (err.code !== "42P01") {
          console.error("session check error:", err.message);
        }
      }
    }

    return next();
  } catch (err) {
    return res.status(401).json({ error: "Token invalide ou expiré" });
  }
};

const requireRole = (...roles) => {
  return (req, res, next) => {
    if (!roles.includes(req.userRole)) {
      return res.status(403).json({ error: "Accès non autorisé" });
    }
    next();
  };
};

module.exports = { authenticate, requireRole };
