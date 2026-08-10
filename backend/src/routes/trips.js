const { Router } = require("express");
const { body } = require("express-validator");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/tripController");

const router = Router();

router.post(
  "/",
  authenticate,
  [
    body("origin_lat").isFloat({ min: -90, max: 90 }),
    body("origin_lng").isFloat({ min: -180, max: 180 }),
    body("dest_lat").isFloat({ min: -90, max: 90 }),
    body("dest_lng").isFloat({ min: -180, max: 180 }),
  ],
  ctrl.startTrip
);
router.get("/active", authenticate, ctrl.getActiveTrip);
router.get("/:id", authenticate, ctrl.getTrip);
router.post("/:id/ping", authenticate, ctrl.pingTrip);
router.post("/:id/arrive", authenticate, ctrl.arriveTrip);
router.post("/:id/cancel", authenticate, ctrl.cancelTrip);

module.exports = router;
