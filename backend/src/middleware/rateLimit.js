const rateLimit = require("express-rate-limit");
const { getRedisClient, isRedisReady } = require("../config/redis");

const skipInTest = () => process.env.NODE_ENV === "test";

/**
 * Redis-backed store for express-rate-limit v7.
 * Falls back to memory store when Redis is unavailable.
 */
class RedisRateLimitStore {
  constructor({ prefix = "rl:", windowMs = 900000 } = {}) {
    this.prefix = prefix;
    this.windowMs = windowMs;
    this.local = new Map();
  }

  _localKey(key) {
    return `${this.prefix}${key}`;
  }

  async increment(key) {
    const full = this._localKey(key);
    const windowSec = Math.ceil(this.windowMs / 1000);
    if (isRedisReady()) {
      try {
        const client = getRedisClient();
        const count = await client.incr(full);
        if (count === 1) await client.expire(full, windowSec);
        const ttl = await client.ttl(full);
        const resetTime = new Date(Date.now() + Math.max(ttl, 1) * 1000);
        return { totalHits: count, resetTime };
      } catch (_) {
        /* fall through to memory */
      }
    }
    const now = Date.now();
    let entry = this.local.get(full);
    if (!entry || entry.resetTime <= now) {
      entry = { totalHits: 0, resetTime: now + this.windowMs };
    }
    entry.totalHits += 1;
    this.local.set(full, entry);
    return { totalHits: entry.totalHits, resetTime: new Date(entry.resetTime) };
  }

  async decrement(key) {
    const full = this._localKey(key);
    if (isRedisReady()) {
      try {
        const client = getRedisClient();
        const n = await client.decr(full);
        if (n < 0) await client.set(full, "0");
        return;
      } catch (_) {
        /* ignore */
      }
    }
    const entry = this.local.get(full);
    if (entry && entry.totalHits > 0) entry.totalHits -= 1;
  }

  async resetKey(key) {
    const full = this._localKey(key);
    if (isRedisReady()) {
      try {
        await getRedisClient().del(full);
      } catch (_) {
        /* ignore */
      }
    }
    this.local.delete(full);
  }
}

const WINDOW_15M = 15 * 60 * 1000;

const authRequestLimiter = rateLimit({
  windowMs: WINDOW_15M,
  max: 5,
  message: { error: "Trop de demandes de code, réessayez dans 15 minutes" },
  standardHeaders: true,
  legacyHeaders: false,
  skip: skipInTest,
  store: new RedisRateLimitStore({ prefix: "rl:auth:req:", windowMs: WINDOW_15M }),
});

const authVerifyLimiter = rateLimit({
  windowMs: WINDOW_15M,
  max: 10,
  message: { error: "Trop de tentatives de vérification, réessayez dans 15 minutes" },
  standardHeaders: true,
  legacyHeaders: false,
  skip: skipInTest,
  store: new RedisRateLimitStore({ prefix: "rl:auth:verify:", windowMs: WINDOW_15M }),
});

const apiLimiter = rateLimit({
  windowMs: WINDOW_15M,
  max: 300,
  message: { error: "Trop de requêtes, réessayez plus tard" },
  standardHeaders: true,
  legacyHeaders: false,
  skip: skipInTest,
  store: new RedisRateLimitStore({ prefix: "rl:api:", windowMs: WINDOW_15M }),
});

/** Soft SOS anti-abuse: 8 SOS / 15 min per user (or IP if unauthenticated). */
const sosLimiter = rateLimit({
  windowMs: WINDOW_15M,
  max: 8,
  message: {
    error:
      "Trop d'alertes envoyées récemment. Attendez quelques minutes ou utilisez l'annuaire d'urgence si besoin immédiat.",
  },
  standardHeaders: true,
  legacyHeaders: false,
  skip: skipInTest,
  keyGenerator: (req) => String(req.userId || req.ip || "anon"),
  validate: { ip: false },
  store: new RedisRateLimitStore({ prefix: "rl:sos:", windowMs: WINDOW_15M }),
});

/**
 * Enforce partner_api_keys.rate_limit (requests per 15-minute window).
 * Uses Redis when available, otherwise in-memory.
 */
const partnerHitLocal = new Map();

const enforcePartnerRateLimit = async (req, res, next) => {
  if (skipInTest()) return next();
  const partner = req.partner;
  if (!partner) return next();

  const limit = Math.max(1, Number(partner.rate_limit) || 1000);
  const key = `rl:partner:${partner.id}`;
  const windowSec = 900;

  try {
    if (isRedisReady()) {
      const client = getRedisClient();
      const count = await client.incr(key);
      if (count === 1) await client.expire(key, windowSec);
      res.setHeader("X-RateLimit-Limit", String(limit));
      res.setHeader("X-RateLimit-Remaining", String(Math.max(0, limit - count)));
      if (count > limit) {
        return res.status(429).json({
          error: "Limite de requêtes partenaire atteinte. Réessayez plus tard.",
        });
      }
      return next();
    }

    const now = Date.now();
    let entry = partnerHitLocal.get(key);
    if (!entry || entry.resetAt <= now) {
      entry = { count: 0, resetAt: now + windowSec * 1000 };
    }
    entry.count += 1;
    partnerHitLocal.set(key, entry);
    res.setHeader("X-RateLimit-Limit", String(limit));
    res.setHeader("X-RateLimit-Remaining", String(Math.max(0, limit - entry.count)));
    if (entry.count > limit) {
      return res.status(429).json({
        error: "Limite de requêtes partenaire atteinte. Réessayez plus tard.",
      });
    }
    return next();
  } catch (err) {
    console.error("partner rate limit error:", err.message);
    return next();
  }
};

module.exports = {
  authRequestLimiter,
  authVerifyLimiter,
  apiLimiter,
  sosLimiter,
  enforcePartnerRateLimit,
  RedisRateLimitStore,
};
