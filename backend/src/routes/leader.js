const { Router } = require("express");
const { authenticate, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/leaderController");

const router = Router();

router.get("/sector/incidents", authenticate, requireRole("leader", "agent"), ctrl.getSectorIncidents);
router.put("/sector/incidents/:id/acknowledge", authenticate, requireRole("leader", "agent"), ctrl.acknowledgeIncident);
router.put("/sector/incidents/:id/resolve", authenticate, requireRole("leader", "agent"), ctrl.resolveIncident);
router.get("/sector/stats", authenticate, requireRole("leader", "agent"), ctrl.getSectorStats);

module.exports = router;