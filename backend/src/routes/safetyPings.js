const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/safetyPingController");

const router = Router();

router.post("/", authenticate, ctrl.schedulePing);
router.get("/active", authenticate, ctrl.getActivePing);
router.get("/mine", authenticate, ctrl.listMyPings);
router.post("/:id/ok", authenticate, ctrl.respondOk);
router.post("/:id/cancel", authenticate, ctrl.cancelPing);

module.exports = router;
