const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/backupController");

const router = Router();

router.put("/contacts", authenticate, ctrl.upsertBackup);
router.get("/contacts", authenticate, ctrl.getBackup);
router.delete("/contacts", authenticate, ctrl.deleteBackup);

module.exports = router;
