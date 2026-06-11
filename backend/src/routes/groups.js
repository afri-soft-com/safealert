const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/groupsController");

const router = Router();

router.get("/", authenticate, ctrl.getMyGroups);
router.post("/", authenticate, ctrl.createGroup);
router.post("/join", authenticate, ctrl.joinGroup);
router.get("/discover", authenticate, ctrl.discoverGroups);
router.get("/:id/members", authenticate, ctrl.getGroupMembers);
router.delete("/:id/leave", authenticate, ctrl.leaveGroup);

module.exports = router;