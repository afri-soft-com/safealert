const features = require("../config/features");

/**
 * Public app version policy for soft / force update prompts.
 * Env: APP_LATEST_VERSION, APP_MIN_VERSION, APP_FORCE_UPDATE, APP_STORE_URL
 */
function versionPayload() {
  const latestVersion = (process.env.APP_LATEST_VERSION || "").trim();
  const minVersion = (process.env.APP_MIN_VERSION || "").trim();
  const forceRaw = process.env.APP_FORCE_UPDATE || "";
  const forceUpdate = ["1", "true", "yes", "on"].includes(String(forceRaw).toLowerCase());
  const storeUrl =
    (process.env.APP_STORE_URL || "").trim() ||
    "https://play.google.com/store/apps/details?id=com.safealert.safealert";

  return {
    minVersion,
    latestVersion,
    forceUpdate,
    storeUrl,
  };
}

function configPayload() {
  const maintenance = features.maintenanceMode();
  const sosEnabled = features.sosEnabled() && !maintenance;
  const banner =
    (process.env.APP_MAINTENANCE_BANNER || "").trim() ||
    (maintenance
      ? "Maintenance en cours. Certaines fonctions peuvent être temporairement indisponibles."
      : "");

  return {
    ...versionPayload(),
    maintenance,
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
    },
  };
}

function getAppVersion(req, res) {
  return res.json(versionPayload());
}

function getAppConfig(req, res) {
  return res.json(configPayload());
}

module.exports = { getAppVersion, getAppConfig, versionPayload, configPayload };
