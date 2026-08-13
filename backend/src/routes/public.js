const { Router } = require("express");
const rateLimit = require("express-rate-limit");
const { getPublicTrip } = require("../controllers/publicTripController");

const router = Router();

const publicTripLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 120,
  message: { error: "Trop de requêtes" },
  standardHeaders: true,
  legacyHeaders: false,
  skip: () => process.env.NODE_ENV === "test",
});

router.get("/trips/:token", publicTripLimiter, getPublicTrip);

module.exports = router;
