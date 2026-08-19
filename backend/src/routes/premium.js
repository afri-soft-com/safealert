const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/premiumController");

const router = Router();

router.get("/status", authenticate, ctrl.getStatus);
router.post("/grant", authenticate, ctrl.grantPremium);
router.post("/revoke", authenticate, ctrl.revokePremium);
router.post("/checkout", authenticate, ctrl.createCheckout);

module.exports = router;
