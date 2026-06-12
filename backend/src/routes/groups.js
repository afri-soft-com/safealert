const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/groupsController");

const router = Router();

router.get("/", authenticate, ctrl.getMyGroups);
router.post("/", authenticate, ctrl.createGroup);
router.post("/join", authenticate, ctrl.joinGroup);
router.get("/discover", authenticate, ctrl.discoverGroups);
router.get("/:id/join-requests", authenticate, ctrl.getJoinRequests);
router.put("/join-requests/:id/approve", authenticate, ctrl.approveJoinRequest);
router.put("/join-requests/:id/reject", authenticate, ctrl.rejectJoinRequest);
router.post("/:id/join", authenticate, ctrl.joinGroupById);
router.get("/:id/members", authenticate, ctrl.getGroupMembers);
router.get("/:id/messages", authenticate, ctrl.getGroupMessages);
router.post("/:id/messages", authenticate, ctrl.postGroupMessage);
router.get("/:id/alerts", authenticate, ctrl.getGroupAlerts);
router.post("/:id/alerts", authenticate, ctrl.postGroupAlert);
router.delete("/:id/leave", authenticate, ctrl.leaveGroup);

module.exports = router;