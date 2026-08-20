const { pool } = require("../config/database");
const features = require("../config/features");

const DEFAULT_MESSAGE =
  "Nous effectuons une mise à jour de la plateforme. Le service sera de retour très bientôt.";

let cache = { at: 0, maintenance: false, message: DEFAULT_MESSAGE };

const readDb = async () => {
  try {
    const r = await pool.query(
      `SELECT key, value FROM app_settings WHERE key IN ('maintenance_mode', 'maintenance_message')`
    );
    const map = Object.fromEntries(r.rows.map((row) => [row.key, row.value]));
    return {
      maintenance: map.maintenance_mode === "true" || map.maintenance_mode === "1",
      message: (map.maintenance_message || "").trim() || DEFAULT_MESSAGE,
    };
  } catch (err) {
    if (err.code !== "42P01") {
      console.error("appSettings read:", err.message);
    }
    return null;
  }
};

const getMaintenance = async () => {
  if (Date.now() - cache.at < 5000 && cache.at) {
    return { maintenance: cache.maintenance, message: cache.message };
  }
  const fromDb = await readDb();
  const envOn = features.maintenanceMode();
  const maintenance = envOn || Boolean(fromDb?.maintenance);
  const message =
    (fromDb?.message && fromDb.message) ||
    (process.env.APP_MAINTENANCE_BANNER || "").trim() ||
    DEFAULT_MESSAGE;
  cache = { at: Date.now(), maintenance, message };
  return { maintenance, message };
};

const setMaintenance = async ({ enabled, message }) => {
  const value = enabled ? "true" : "false";
  const msg = (message || "").trim() || DEFAULT_MESSAGE;
  await pool.query(
    `INSERT INTO app_settings (key, value, updated_at)
     VALUES ('maintenance_mode', $1, NOW())
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`,
    [value]
  );
  await pool.query(
    `INSERT INTO app_settings (key, value, updated_at)
     VALUES ('maintenance_message', $1, NOW())
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`,
    [msg]
  );
  cache = { at: 0, maintenance: enabled, message: msg };
  return getMaintenance();
};

const isStaffRole = (role) => role === "admin" || role === "platform_admin";
const isSuperAdmin = (role) => role === "platform_admin";

module.exports = {
  DEFAULT_MESSAGE,
  getMaintenance,
  setMaintenance,
  isStaffRole,
  isSuperAdmin,
};
