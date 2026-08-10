const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/neighborhoodController");

const router = Router();

router.get("/", authenticate, ctrl.listSubscriptions);
router.post("/subscribe", authenticate, ctrl.subscribe);
router.delete("/:id", authenticate, ctrl.unsubscribe);

module.exports = router;
