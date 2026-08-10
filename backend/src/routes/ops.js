const { Router } = require("express");
const { authenticate, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/opsController");

const router = Router();

router.get(
  "/queue",
  authenticate,
  requireRole("leader", "agent", "platform_admin"),
  ctrl.getOpsQueue
);
router.get(
  "/reports/sector",
  authenticate,
  requireRole("leader", "agent", "platform_admin"),
  ctrl.exportSectorReport
);

module.exports = router;
