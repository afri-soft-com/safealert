const { Router } = require("express");
const { getAppVersion } = require("../controllers/appVersionController");

const router = Router();

/** Public — no auth. Used by mobile for soft / force update checks. */
router.get("/version", getAppVersion);

module.exports = router;
