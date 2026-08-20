const jwt = require("jsonwebtoken");
const { pool } = require("../config/database");
const { isStaffRole, isSuperAdmin } = require("../services/appSettings");

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

    const skipLive = process.env.VITEST || process.env.NODE_ENV === "test";
    if (!skipLive) {
      try {
        const live = await pool.query(
          `SELECT role, COALESCE(is_active, true) AS is_active FROM users WHERE id = $1`,
          [decoded.userId]
        );
        if (live.rows.length > 0) {
          if (live.rows[0].is_active === false) {
            return res.status(403).json({ error: "Ce compte a été désactivé." });
          }
          req.userRole = live.rows[0].role || decoded.role;
        }
      } catch (err) {
        if (err.code !== "42703") {
          console.error("auth live role:", err.message);
        }
      }
    }

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
        if (err.code !== "42P01") {
          console.error("session check error:", err.message);
        }
      }
    }

    return next();
  } catch (err) {
    return res.status(401).json({ error: "Session expirée. Reconnectez-vous." });
  }
};

const requireRole = (...roles) => {
  return (req, res, next) => {
    if (!roles.includes(req.userRole)) {
      return res.status(403).json({ error: "Accès non autorisé pour votre profil." });
    }
    next();
  };
};

const requireStaff = requireRole("admin", "platform_admin");
const requireSuperAdmin = requireRole("platform_admin");

module.exports = {
  authenticate,
  requireRole,
  requireStaff,
  requireSuperAdmin,
  isStaffRole,
  isSuperAdmin,
};
