const { Router } = require("express");
const { body } = require("express-validator");
const { authenticate } = require("../middleware/auth");
const { authRequestLimiter, authVerifyLimiter } = require("../middleware/rateLimit");
const ctrl = require("../controllers/authController");

const router = Router();

router.post(
  "/request-code",
  authRequestLimiter,
  [body("phone").isMobilePhone().withMessage("Numéro invalide")],
  ctrl.requestCode
);
router.post(
  "/verify-code",
  authVerifyLimiter,
  [body("phone").isMobilePhone(), body("code").isLength({ min: 6, max: 6 })],
  ctrl.verifyCode
);
router.get("/profile", authenticate, ctrl.getProfile);
router.put("/profile", authenticate, ctrl.updateProfile);
router.put(
  "/position",
  authenticate,
  [body("lat").isFloat({ min: -90, max: 90 }), body("lng").isFloat({ min: -180, max: 180 })],
  ctrl.updatePosition
);
router.put("/fcm-token", authenticate, ctrl.updateFCMToken);
router.delete("/account", authenticate, ctrl.deleteAccount);

module.exports = router;
