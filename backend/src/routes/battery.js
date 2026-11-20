const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/batteryController");

const router = Router();

router.post("/low", authenticate, ctrl.reportLowBattery);

module.exports = router;
