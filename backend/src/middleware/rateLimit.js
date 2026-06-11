const rateLimit = require("express-rate-limit");

const skipInTest = () => process.env.NODE_ENV === "test";

const authRequestLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  message: { error: "Trop de demandes de code, réessayez dans 15 minutes" },
  standardHeaders: true,
  legacyHeaders: false,
  skip: skipInTest,
});

const authVerifyLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: { error: "Trop de tentatives de vérification, réessayez dans 15 minutes" },
  standardHeaders: true,
  legacyHeaders: false,
  skip: skipInTest,
});

const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 300,
  message: { error: "Trop de requêtes, réessayez plus tard" },
  standardHeaders: true,
  legacyHeaders: false,
  skip: skipInTest,
});

module.exports = { authRequestLimiter, authVerifyLimiter, apiLimiter };
