const features = require("../config/features");
const { getMaintenance } = require("../services/appSettings");

/** Keep in sync with frontend/pubspec.yaml (version name, before +build). */
const DEFAULT_MOBILE_VERSION = "1.0.8";
/** Keep in sync with admin-web/package.json. */
const DEFAULT_ADMIN_WEB_VERSION = "1.0.2";

/**
 * Public app version policy for soft / force update prompts.
 * Env: APP_LATEST_VERSION, APP_MIN_VERSION, APP_FORCE_UPDATE, APP_STORE_URL,
 *      ADMIN_WEB_VERSION, ADMIN_WEB_URL
 */
function versionPayload() {
  const latestVersion =
    (process.env.APP_LATEST_VERSION || "").trim() || DEFAULT_MOBILE_VERSION;
  const minVersion = (process.env.APP_MIN_VERSION || "").trim();
  const forceRaw = process.env.APP_FORCE_UPDATE || "";
  const forceUpdate = ["1", "true", "yes", "on"].includes(String(forceRaw).toLowerCase());
  const storeUrl =
    (process.env.APP_STORE_URL || "").trim() ||
    "https://play.google.com/store/apps/details?id=com.safealert.safealert";
  const adminWebVersion =
    (process.env.ADMIN_WEB_VERSION || "").trim() || DEFAULT_ADMIN_WEB_VERSION;
  const adminWebUrl =
    (process.env.ADMIN_WEB_URL || "").trim() ||
    "https://safealert-admin.onrender.com";

  return {
    minVersion,
    latestVersion,
    forceUpdate,
    storeUrl,
    adminWebVersion,
    adminWebUrl,
  };
}

async function configPayload() {
  const m = await getMaintenance();
  const sosEnabled = features.sosEnabled();
  const banner = m.maintenance
    ? m.message
    : ((process.env.APP_MAINTENANCE_BANNER || "").trim() || "");

  return {
    ...versionPayload(),
    maintenance: m.maintenance,
    sosEnabled,
    maintenanceBanner: banner,
    features: {
      checkIn: features.checkIn(),
      safeTrip: features.safeTrip(),
      liveStatus: features.liveStatus(),
      offlineQueue: features.offlineQueue(),
      publicShare: features.publicShare(),
      safetyPing: features.safetyPing(),
      contactBackup: features.contactBackup(),
      circleInvite: features.circleInvite(),
      corridors: features.corridors(),
      premium: features.premium(),
      heatmap: features.heatmap(),
    },
  };
}

function getAppVersion(req, res) {
  return res.json(versionPayload());
}

async function getAppConfig(req, res) {
  return res.json(await configPayload());
}

module.exports = {
  getAppVersion,
  getAppConfig,
  versionPayload,
  configPayload,
  DEFAULT_MOBILE_VERSION,
  DEFAULT_ADMIN_WEB_VERSION,
};
