const { Router } = require("express");
const { body } = require("express-validator");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/sosController");

const router = Router();

router.post("/trigger", authenticate, [
  body("lat").isFloat({ min: -90, max: 90 }),
  body("lng").isFloat({ min: -180, max: 180 }),
], ctrl.triggerSOS);

router.post("/:id/cancel", authenticate, ctrl.cancelSOS);
router.post("/cancel", authenticate, ctrl.cancelLatestSOS);
router.get("/my", authenticate, ctrl.getMyAlerts);

module.exports = router;
