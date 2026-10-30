const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/neighborhoodController");

const router = Router();

router.get("/", authenticate, ctrl.listSubscriptions);
router.get("/digest", authenticate, ctrl.getDigest);
router.post("/subscribe", authenticate, ctrl.subscribe);
router.post("/:id/send-now", authenticate, ctrl.sendNow);
router.patch("/:id", authenticate, ctrl.updateSubscription);
router.delete("/:id", authenticate, ctrl.unsubscribe);

module.exports = router;
