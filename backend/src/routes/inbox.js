const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/inboxController");

const router = Router();

router.get("/", authenticate, ctrl.listInbox);
router.post("/read-all", authenticate, ctrl.markAllRead);
router.post("/:id/read", authenticate, ctrl.markRead);

module.exports = router;
