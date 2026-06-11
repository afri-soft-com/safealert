const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/mapController");

const router = Router();

router.get("/incidents", ctrl.getIncidents);
router.post("/incidents", authenticate, ctrl.reportIncident);
router.post("/incidents/:id/verify", authenticate, ctrl.verifyIncident);
router.get("/stats", authenticate, ctrl.getStats);
router.get("/heatmap", ctrl.getHeatmap);

module.exports = router;
