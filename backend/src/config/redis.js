const { log, warn, error: logError } = require("../utils/logger");

let client = null;
let connected = false;

const initRedis = async () => {
  if (!process.env.REDIS_URL) {
    warn("Redis not configured — alert cache disabled");
    return;
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
  } catch (err) {
    warn("Redis connection failed — cache disabled:", err.message);
    client = null;
    connected = false;
  }
};

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
    const keys = await client.keys("map:incidents:*");
    if (keys.length > 0) await client.del(keys);
  } catch (err) {
    console.error("Redis invalidate error:", err.message);
  }
};

module.exports = {
  initRedis,
  isRedisReady,
  cacheGet,
  cacheSet,
  invalidateActiveAlerts,
};
