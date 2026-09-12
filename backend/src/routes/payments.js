const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/paymentsController");

const router = Router();

router.get("/config", authenticate, ctrl.getConfig);
router.post("/premium/intents", authenticate, ctrl.createIntent);
router.post("/premium/intents/:id/start", authenticate, ctrl.startCharge);
router.get("/premium/intents/:id", authenticate, ctrl.getIntent);

module.exports = router;
