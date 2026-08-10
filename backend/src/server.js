require("dotenv").config();

const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const http = require("http");
const { Server } = require("socket.io");
const { apiLimiter } = require("./middleware/rateLimit");
const { pool } = require("./config/database");
const { initFCM } = require("./config/firebase");
const { initSMS } = require("./services/sms");
const { initRedis, isRedisReady } = require("./config/redis");
const { socketRedisAdapter } = require("./config/features");
const { log, warn } = require("./utils/logger");

const isProduction = process.env.NODE_ENV === "production";
const jwtSecret = process.env.JWT_SECRET || "";

if (isProduction) {
  if (!jwtSecret || jwtSecret.length < 32 || jwtSecret === "change-me-in-production") {
    console.error("JWT_SECRET must be set to a strong value (32+ chars) in production");
    process.exit(1);
  }
}

const authRoutes = require("./routes/auth");
const sosRoutes = require("./routes/sos");
const contactsRoutes = require("./routes/contacts");
const annuaireRoutes = require("./routes/annuaire");
const mapRoutes = require("./routes/map");
const leaderRoutes = require("./routes/leader");
const groupsRoutes = require("./routes/groups");
const reportRoutes = require("./routes/report");
const partnerRoutes = require("./routes/partner");
const adminRoutes = require("./routes/admin");
const historyRoutes = require("./routes/history");
const checkinRoutes = require("./routes/checkin");
const tripsRoutes = require("./routes/trips");
const liveStatusRoutes = require("./routes/liveStatus");
const trustZonesRoutes = require("./routes/trustZones");
const neighborhoodRoutes = require("./routes/neighborhood");
const backupRoutes = require("./routes/backup");
const premiumRoutes = require("./routes/premium");
const opsRoutes = require("./routes/ops");

const app = express();
const server = http.createServer(app);

const path = require("path");

const defaultDevOrigins = ["http://localhost:5173", "http://127.0.0.1:5173"];
const corsOrigin = process.env.CORS_ORIGIN;

function resolveCorsOrigin() {
  if (corsOrigin === "*") return "*";
  if (corsOrigin && corsOrigin.trim()) {
    return corsOrigin.split(",").map((o) => o.trim()).filter(Boolean);
  }
  if (!isProduction) return defaultDevOrigins;
  return null;
}

const allowedOrigins = resolveCorsOrigin();

if (isProduction && !allowedOrigins) {
  console.error(
    "CORS_ORIGIN must be set in production (comma-separated origins, or * for public API)"
  );
  process.exit(1);
}

const corsOptions =
  allowedOrigins === "*"
    ? {}
    : {
        origin(origin, callback) {
          if (!origin || allowedOrigins.includes(origin)) {
            return callback(null, true);
          }
          return callback(null, false);
        },
      };

const socketCors =
  allowedOrigins === "*" || !allowedOrigins
    ? { origin: "*" }
    : { origin: allowedOrigins };

const io = new Server(server, { cors: socketCors });
app.set("io", io);

io.on("connection", (socket) => {
  socket.on("authenticate", (payload) => {
    const userId =
      typeof payload === "string"
        ? payload
        : payload && typeof payload === "object"
          ? payload.userId || payload.user_id
          : null;
    if (userId && typeof userId === "string" && userId.length < 80) {
      socket.join(`user:${userId}`);
    }
  });
});

app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors(corsOptions));
app.use(express.json());
app.use("/api", apiLimiter);

if (isProduction) {
  app.set("trust proxy", 1);
}

app.get("/health", (req, res) => {
  res.json({
    status: "ok",
    service: "SafeAlert API",
    version: "1.0.0",
    redis: isRedisReady() ? "up" : "down",
  });
});

app.get("/health/ready", async (req, res) => {
  try {
    await pool.query("SELECT 1");
    return res.json({
      status: "ready",
      service: "SafeAlert API",
      db: "ok",
      redis: isRedisReady() ? "ok" : "disabled",
    });
  } catch (err) {
    console.error("Readiness check failed:", err.message);
    return res.status(503).json({ status: "not_ready", db: "error" });
  }
});

app.use("/api/auth", authRoutes);
app.use("/api/sos", sosRoutes);
app.use("/api/contacts", contactsRoutes);
app.use("/api/annuaire", annuaireRoutes);
app.use("/api/map", mapRoutes);
app.use("/api/leader", leaderRoutes);
app.use("/api/groups", groupsRoutes);
app.use("/api/report", reportRoutes);
app.use("/api/partner", partnerRoutes);
app.use("/api/admin", adminRoutes);
app.use("/api/history", historyRoutes);
app.use("/api/checkin", checkinRoutes);
app.use("/api/trips", tripsRoutes);
app.use("/api/live-status", liveStatusRoutes);
app.use("/api/trust-zones", trustZonesRoutes);
app.use("/api/neighborhood", neighborhoodRoutes);
app.use("/api/backup", backupRoutes);
app.use("/api/premium", premiumRoutes);
app.use("/api/ops", opsRoutes);

const adminWebDist = process.env.ADMIN_WEB_DIST;
if (adminWebDist) {
  const adminPath = path.resolve(adminWebDist);
  app.use("/admin", express.static(adminPath));
  app.get("/admin/*", (req, res) => {
    res.sendFile(path.join(adminPath, "index.html"));
  });
}

app.use((req, res) => {
  res.status(404).json({ error: "Route non trouvée", path: req.path });
});

app.use((err, req, res, next) => {
  console.error("Unhandled error:", err);
  const status = err.status || err.statusCode || 500;
  const message = status < 500 && err.message ? err.message : "Erreur interne du serveur";
  res.status(status).json({ error: message });
});

const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || "0.0.0.0";

async function attachSocketRedisAdapter() {
  if (!socketRedisAdapter() || !process.env.REDIS_URL) return;
  try {
    const { createClient } = require("redis");
    const { createAdapter } = require("@socket.io/redis-adapter");
    const pubClient = createClient({ url: process.env.REDIS_URL });
    const subClient = pubClient.duplicate();
    pubClient.on("error", (err) => warn("Redis pub adapter:", err.message));
    subClient.on("error", (err) => warn("Redis sub adapter:", err.message));
    await Promise.all([pubClient.connect(), subClient.connect()]);
    io.adapter(createAdapter(pubClient, subClient));
    log("Socket.io Redis adapter enabled");
  } catch (err) {
    warn("Socket.io Redis adapter skipped:", err.message);
  }
}

function startBackgroundJobs() {
  if (process.env.NODE_ENV === "test" || process.env.VITEST) return;

  const { processOverdueTrips } = require("./controllers/tripController");
  const { purgeExpired } = require("./controllers/liveStatusController");
  const { sendDigests } = require("./controllers/neighborhoodController");

  // Overdue safe trips — every 60s
  setInterval(() => {
    processOverdueTrips().catch((err) => warn("trip overdue job:", err.message));
  }, 60_000);

  // Purge expired live status — every 2 min
  setInterval(() => {
    purgeExpired().catch((err) => warn("live status purge:", err.message));
  }, 120_000);

  // Neighborhood digests — every 15 min
  setInterval(() => {
    sendDigests().catch((err) => warn("neighborhood digest:", err.message));
  }, 15 * 60_000);

  // Purge evidence past retention — daily
  setInterval(async () => {
    try {
      await pool.query(`DELETE FROM incident_evidence WHERE retention_until < NOW()`);
    } catch (err) {
      warn("evidence purge:", err.message);
    }
  }, 24 * 60 * 60_000);
}

async function bootstrap() {
  initFCM();
  initSMS();
  await initRedis().catch((err) => console.warn("Redis init skipped:", err.message));
  await attachSocketRedisAdapter();
  startBackgroundJobs();

  if (process.env.NODE_ENV !== "test" && !process.env.VITEST) {
    server.listen(PORT, HOST, () => {
      log(`SafeAlert API running on ${HOST}:${PORT}`);
    });
  }
}

bootstrap().catch((err) => {
  console.error("Bootstrap failed:", err);
  process.exit(1);
});

module.exports = { app, server, io };
