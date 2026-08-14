const { Router } = require("express");
const { body } = require("express-validator");
const { authenticate } = require("../middleware/auth");
const { sosLimiter } = require("../middleware/rateLimit");
const ctrl = require("../controllers/sosController");
const live = require("../controllers/liveStatusController");

const router = Router();

router.post("/trigger", authenticate, sosLimiter, [
  body("lat").isFloat({ min: -90, max: 90 }),
  body("lng").isFloat({ min: -180, max: 180 }),
], ctrl.triggerSOS);

router.post("/:id/cancel", authenticate, ctrl.cancelSOS);
router.post("/cancel", authenticate, ctrl.cancelLatestSOS);
router.get("/my", authenticate, ctrl.getMyAlerts);

/** Live status during active SOS (also under /api/live-status) */
router.post("/live", authenticate, live.upsertLiveStatus);
router.get("/live/:incidentId", authenticate, live.getLiveStatus);

module.exports = router;
