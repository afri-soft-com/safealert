const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/liveCircleController");

const router = Router();

router.use(authenticate);
router.get("/", ctrl.listMine);
router.post("/", ctrl.createCircle);
router.post("/join", ctrl.joinCircle);
router.patch("/:id/share", ctrl.setShare);
router.get("/:id/members", ctrl.membersLive);

module.exports = router;
