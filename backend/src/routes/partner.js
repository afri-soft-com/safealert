const { Router } = require("express");
const { authenticate, requireRole } = require("../middleware/auth");
const { authenticatePartner } = require("../middleware/partnerAuth");
const ctrl = require("../controllers/partnerController");

const router = Router();

router.post("/register", authenticate, requireRole("platform_admin"), ctrl.registerPartner);
router.get("/stats", authenticatePartner, ctrl.getPublicStats);
router.get("/incidents", authenticatePartner, ctrl.getPublicIncidents);
router.get("/heatmap", authenticatePartner, ctrl.getPublicHeatmap);

module.exports = router;