const { Router } = require("express");
const { authenticate, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/reportController");

const router = Router();

router.get("/", authenticate, requireRole("leader", "agent"), ctrl.generateReport);

module.exports = router;