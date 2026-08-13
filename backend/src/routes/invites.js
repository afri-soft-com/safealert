const { Router } = require("express");
const rateLimit = require("express-rate-limit");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/inviteController");

const router = Router();

const inviteAcceptLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  message: { error: "Trop de tentatives, réessayez plus tard" },
  standardHeaders: true,
  legacyHeaders: false,
  skip: () => process.env.NODE_ENV === "test",
});

router.post("/circle", authenticate, ctrl.createCircleInvite);
router.post("/circle/accept", authenticate, inviteAcceptLimiter, ctrl.acceptCircleInvite);
router.get("/circle/:code", ctrl.peekInvite);

module.exports = router;
