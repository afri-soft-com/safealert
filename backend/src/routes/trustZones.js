const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/trustZoneController");

const router = Router();

router.get("/", authenticate, ctrl.listZones);
router.post("/", authenticate, ctrl.createZone);
router.delete("/:id", authenticate, ctrl.deleteZone);

module.exports = router;
