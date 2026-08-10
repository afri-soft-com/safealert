const { Router } = require("express");
const { authenticate, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/reportController");

const router = Router();

router.get("/", authenticate, requireRole("leader", "agent", "platform_admin"), ctrl.generateReport);

module.exports = router;