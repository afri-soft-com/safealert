const jwt = require("jsonwebtoken");
const { pool } = require("../config/database");
const { getMaintenance, isStaffRole } = require("../services/appSettings");

const ALWAYS_OPEN = [
  /^\/health/,
  /^\/api\/auth/,
  /^\/api\/app/,
  /^\/api\/annuaire/,
  /^\/api\/sos/,
  /^\/api\/public/,
  /^\/t\//,
  /^\/invite\//,
];

const staffFromToken = async (req) => {
  const header = req.headers.authorization;
  if (!header || !header.startsWith("Bearer ")) return false;
  try {
    const decoded = jwt.verify(header.split(" ")[1], process.env.JWT_SECRET);
    if (isStaffRole(decoded.role)) return true;
    const live = await pool.query(
      `SELECT role, COALESCE(is_active, true) AS is_active FROM users WHERE id = $1`,
      [decoded.userId]
    );
    const row = live.rows[0];
    return Boolean(row && row.is_active !== false && isStaffRole(row.role));
  } catch {
    return false;
  }
};

const maintenanceGate = async (req, res, next) => {
  if (process.env.VITEST || process.env.NODE_ENV === "test") return next();
  try {
    const state = await getMaintenance();
    if (!state.maintenance) return next();
    if (ALWAYS_OPEN.some((re) => re.test(req.path))) return next();
    if (await staffFromToken(req)) return next();
    return res.status(503).json({
      error: state.message,
      maintenance: true,
      code: "MAINTENANCE",
    });
  } catch (err) {
    console.error("maintenanceGate:", err.message);
    return next();
  }
};

module.exports = { maintenanceGate };
