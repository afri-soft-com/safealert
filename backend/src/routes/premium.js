const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/premiumController");

const router = Router();

router.get("/status", authenticate, ctrl.getStatus);
router.post("/grant", authenticate, ctrl.grantPremium);

module.exports = router;
