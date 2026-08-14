/**
 * Public app version policy for soft / force update prompts.
 * Env: APP_LATEST_VERSION, APP_MIN_VERSION, APP_FORCE_UPDATE, APP_STORE_URL
 */
function getAppVersion(req, res) {
  const latestVersion = (process.env.APP_LATEST_VERSION || "").trim();
  const minVersion = (process.env.APP_MIN_VERSION || "").trim();
  const forceRaw = process.env.APP_FORCE_UPDATE || "";
  const forceUpdate = ["1", "true", "yes", "on"].includes(String(forceRaw).toLowerCase());
  const storeUrl =
    (process.env.APP_STORE_URL || "").trim() ||
    "https://play.google.com/store/apps/details?id=com.safealert.safealert";

  return res.json({
    minVersion,
    latestVersion,
    forceUpdate,
    storeUrl,
  });
}

module.exports = { getAppVersion };
