const { Router } = require("express");
const { getAppVersion, getAppConfig } = require("../controllers/appVersionController");

const router = Router();

/** Public — no auth. Used by mobile for soft / force update checks. */
router.get("/version", getAppVersion);

/** Public — remote feature flags, maintenance banner, SOS kill switch. */
router.get("/config", getAppConfig);

module.exports = router;
