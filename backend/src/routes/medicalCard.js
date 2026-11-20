const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/medicalCardController");

const router = Router();

router.use(authenticate);
router.get("/", ctrl.getMine);
router.put("/", ctrl.saveMine);
router.get("/:userId", ctrl.getForSos);

module.exports = router;
