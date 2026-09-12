const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/premiumController");
const payments = require("../controllers/paymentsController");

const router = Router();

router.get("/status", authenticate, ctrl.getStatus);
router.post("/grant", authenticate, ctrl.grantPremium);
router.post("/revoke", authenticate, ctrl.revokePremium);
router.post("/checkout", authenticate, ctrl.createCheckout);
router.get("/plans", authenticate, payments.listPlans);
router.post("/mobile-money", authenticate, payments.startMobileMoney);
router.get("/payments/:id", authenticate, payments.getPaymentStatus);

module.exports = router;
