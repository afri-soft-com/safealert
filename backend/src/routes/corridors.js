const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/corridorsController");

const router = Router();

router.get("/nearby", authenticate, ctrl.listNearby);
router.get("/suggest", authenticate, ctrl.suggestRoutes);

module.exports = router;
