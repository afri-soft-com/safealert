const { Router } = require("express");
const { authenticate, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/leaderController");
const dispatch = require("../controllers/dispatchController");

const router = Router();
const roles = ["leader", "agent", "platform_admin"];

router.get("/sector/incidents", authenticate, requireRole(...roles), ctrl.getSectorIncidents);
router.put("/sector/incidents/:id/acknowledge", authenticate, requireRole(...roles), ctrl.acknowledgeIncident);
router.put("/sector/incidents/:id/resolve", authenticate, requireRole(...roles), ctrl.resolveIncident);
router.get("/sector/stats", authenticate, requireRole(...roles), ctrl.getSectorStats);

/** Field dispatch */
router.post("/incidents/:id/assign", authenticate, requireRole(...roles), dispatch.assignAgent);
router.post("/incidents/:id/en-route", authenticate, requireRole(...roles), dispatch.markEnRoute);
router.post("/incidents/:id/close", authenticate, requireRole(...roles), dispatch.closeWithReason);
router.get("/incidents/:id/chat", authenticate, requireRole(...roles), dispatch.getChat);
router.post("/incidents/:id/chat", authenticate, requireRole(...roles), dispatch.postChat);
router.get("/incidents/:id/citizen-status", authenticate, dispatch.getCitizenDispatch);
router.get("/sectors", authenticate, requireRole(...roles), dispatch.listMySectors);
router.post("/sectors", authenticate, requireRole(...roles), dispatch.upsertSectorGeofence);

module.exports = router;
