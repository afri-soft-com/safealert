const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/liveStatusController");

const router = Router();

router.post("/", authenticate, ctrl.upsertLiveStatus);
router.get("/:incidentId", authenticate, ctrl.getLiveStatus);

module.exports = router;
