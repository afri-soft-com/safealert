const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/checkInController");

const router = Router();

router.post("/", authenticate, ctrl.createCheckIn);
router.get("/mine", authenticate, ctrl.listMyCheckIns);

module.exports = router;
