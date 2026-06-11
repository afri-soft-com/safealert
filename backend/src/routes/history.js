const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/historyController");

const router = Router();

router.get("/", authenticate, ctrl.getHistory);

module.exports = router;
