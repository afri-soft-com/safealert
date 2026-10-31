const features = require("../config/features");
const { getMaintenance } = require("../services/appSettings");
const { getHomeTilesVisibility } = require("../services/homeTiles");

/** Soft-update target — must match (or trail) the build actually on the stores. */
const DEFAULT_MOBILE_VERSION = "1.0.72";
/** Android versionCode / iOS CFBundleVersion soft target (optional). */
const DEFAULT_MOBILE_BUILD = 100;
/** Soft-update target for admin-web (bump ahead of a deploy to show the banner). */
const DEFAULT_ADMIN_WEB_VERSION = "1.0.16";

/**
 * Public app version policy for soft / force update prompts.
 * Env: APP_LATEST_VERSION, APP_LATEST_BUILD, APP_MIN_VERSION, APP_FORCE_UPDATE,
 *      APP_STORE_URL, APP_STORE_URL_IOS, ADMIN_WEB_VERSION, ADMIN_WEB_URL
 */
function versionPayload() {
  const latestVersion =
    (process.env.APP_LATEST_VERSION || "").trim() || DEFAULT_MOBILE_VERSION;
  const latestBuildParsed = Number.parseInt(
    String(process.env.APP_LATEST_BUILD || DEFAULT_MOBILE_BUILD).trim(),
    10
  );
  const latestBuild = Number.isFinite(latestBuildParsed) ? latestBuildParsed : DEFAULT_MOBILE_BUILD;
  const minVersion = (process.env.APP_MIN_VERSION || "").trim();
  const forceRaw = process.env.APP_FORCE_UPDATE || "";
  const forceUpdate = ["1", "true", "yes", "on"].includes(String(forceRaw).toLowerCase());
  const storeUrl =
    (process.env.APP_STORE_URL || "").trim() ||
    "https://play.google.com/store/apps/details?id=com.safealert.safealert";
  const iosStoreUrl =
    (process.env.APP_STORE_URL_IOS || "").trim() ||
    "https://apps.apple.com/app/id6824983610";
  const adminWebVersion =
    (process.env.ADMIN_WEB_VERSION || "").trim() || DEFAULT_ADMIN_WEB_VERSION;
  const adminWebUrl =
    (process.env.ADMIN_WEB_URL || "").trim() ||
    "https://safealert-admin.onrender.com";

  return {
    minVersion,
    latestVersion,
    latestBuild,
    forceUpdate,
    storeUrl,
    iosStoreUrl,
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
  let fcmConfigured = false;
  let smsConfigured = false;
  try {
    fcmConfigured = require("../config/firebase").isFcmConfigured();
  } catch (_) {
    /* ignore */
  }
  try {
    smsConfigured = require("../services/sms").isSMSConfigured();
  } catch (_) {
    /* ignore */
  }

  const homeTiles = await getHomeTilesVisibility();

  return {
    ...versionPayload(),
    maintenance: m.maintenance,
    sosEnabled,
    maintenanceBanner: banner,
    pushConfigured: fcmConfigured,
    smsConfigured,
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
      heatmap: features.heatmap() && homeTiles.heatmap !== false,
      fakeCall: features.fakeCall() && homeTiles.fake_call !== false,
      arrivalTimer: features.arrivalTimer() && homeTiles.safety_ping !== false,
      sosAudio: features.sosAudio(),
      sosPublicShare: features.sosPublicShare(),
      communeBroadcast: features.communeBroadcast(),
      liveCircles: features.liveCircles() && homeTiles.live_circles !== false,
      sosMediation: features.sosMediation(),
      neighborhoodWatch:
        features.neighborhoodWatch() && homeTiles.neighborhood !== false,
      witnessEvidence: features.witnessEvidence(),
      reliabilityScore: features.reliabilityScore(),
      trustZones: features.trustZones() && homeTiles.trust_zones !== false,
      homeTiles,
    },
  };
}

function getAppVersion(req, res) {
  res.set("Cache-Control", "no-store, no-cache, must-revalidate");
  return res.json(versionPayload());
}

async function getAppConfig(req, res) {
  res.set("Cache-Control", "no-store, no-cache, must-revalidate");
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
