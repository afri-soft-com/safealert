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
          // Explicit revoke stays a logout. A missing row (insert failed, or
          // iOS killed the app before the device row was durable) is restored
          // so a still-valid JWT is not thrown away on the next cold start.
          const revoked = await pool.query(
            `SELECT 1 FROM user_devices
             WHERE user_id = $1 AND session_jti = $2 AND revoked_at IS NOT NULL
             LIMIT 1`,
            [decoded.userId, decoded.jti]
          );
          if (revoked.rows.length > 0) {
            return res.status(401).json({ error: "Session expirée. Reconnectez-vous." });
          }
          const deviceId = decoded.deviceId || `restored-${decoded.jti}`;
          await pool.query(
            `INSERT INTO user_devices (user_id, device_id, session_jti, last_seen_at)
             VALUES ($1, $2, $3, NOW())
             ON CONFLICT (user_id, device_id) DO UPDATE SET
               session_jti = EXCLUDED.session_jti,
               revoked_at = NULL,
               last_seen_at = NOW()
             WHERE user_devices.revoked_at IS NOT NULL
                OR user_devices.session_jti IS NULL
                OR user_devices.session_jti = EXCLUDED.session_jti`,
            [decoded.userId, deviceId, decoded.jti]
          );
          const again = await pool.query(
            `SELECT id FROM user_devices
             WHERE user_id = $1 AND session_jti = $2 AND revoked_at IS NULL`,
            [decoded.userId, decoded.jti]
          );
          if (again.rows.length === 0) {
            // Do not 401 a signed, unrevoked JWT. iOS was wiping the local
            // session on every cold start when the device row could not be
            // rebound (newer row on the same device id).
            console.error("session rebind skipped; keeping valid JWT", decoded.userId);
          }
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
