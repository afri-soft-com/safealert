const { log, warn, error: logError } = require("../utils/logger");

let client = null;
let connected = false;

const initRedis = async () => {
  if (!process.env.REDIS_URL) {
    warn("Redis not configured — alert cache disabled");
    return null;
  }
  try {
    const { createClient } = require("redis");
    client = createClient({ url: process.env.REDIS_URL });
    client.on("error", (err) => {
      logError("Redis error:", err.message);
      connected = false;
    });
    await client.connect();
    connected = true;
    log("Redis connected");
    return client;
  } catch (err) {
    warn("Redis connection failed — cache disabled:", err.message);
    client = null;
    connected = false;
    return null;
  }
};

const getRedisClient = () => (isRedisReady() ? client : null);

const isRedisReady = () => connected && client?.isOpen;

const cacheGet = async (key) => {
  if (!isRedisReady()) return null;
  try {
    return await client.get(key);
  } catch (err) {
    console.error("Redis GET error:", err.message);
    return null;
  }
};

const cacheSet = async (key, value, ttlSeconds = 60) => {
  if (!isRedisReady()) return;
  try {
    await client.setEx(key, ttlSeconds, value);
  } catch (err) {
    console.error("Redis SET error:", err.message);
  }
};

const invalidateActiveAlerts = async () => {
  if (!isRedisReady()) return;
  try {
    // SCAN plutôt que KEYS (non bloquant)
    let cursor = 0;
    const toDelete = [];
    do {
      const result = await client.scan(cursor, { MATCH: "map:incidents:*", COUNT: 100 });
      cursor = result.cursor;
      toDelete.push(...result.keys);
    } while (cursor !== 0);
    if (toDelete.length > 0) await client.del(toDelete);
  } catch (err) {
    console.error("Redis invalidate error:", err.message);
  }
};

/** Compteur OTP par téléphone (fenêtre glissante). */
const incrPhoneOtp = async (phone, windowSeconds = 900) => {
  if (!isRedisReady()) return null;
  const key = `otp:phone:${phone}`;
  try {
    const count = await client.incr(key);
    if (count === 1) await client.expire(key, windowSeconds);
    return count;
  } catch (err) {
    console.error("Redis OTP incr error:", err.message);
    return null;
  }
};

module.exports = {
  initRedis,
  getRedisClient,
  isRedisReady,
  cacheGet,
  cacheSet,
  invalidateActiveAlerts,
  incrPhoneOtp,
};
