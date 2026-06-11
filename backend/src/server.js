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
const { initRedis } = require("./config/redis");
const { log } = require("./utils/logger");

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
const historyRoutes = require("./routes/history");

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });
app.set("io", io);

const corsOrigin = process.env.CORS_ORIGIN;
app.use(helmet({ contentSecurityPolicy: false }));
app.use(
  cors(
    corsOrigin && corsOrigin !== "*"
      ? { origin: corsOrigin.split(",").map((o) => o.trim()) }
      : {}
  )
);
app.use(express.json());
app.use("/api", apiLimiter);

if (isProduction) {
  app.set("trust proxy", 1);
}

app.get("/health", (req, res) => {
  res.json({ status: "ok", service: "SafeAlert API", version: "1.0.0" });
});

app.get("/health/ready", async (req, res) => {
  try {
    await pool.query("SELECT 1");
    return res.json({ status: "ready", service: "SafeAlert API", db: "ok" });
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
app.use("/api/history", historyRoutes);

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
const HOST = process.env.HOST || '0.0.0.0';

initFCM();
initSMS();
initRedis().catch((err) => console.warn("Redis init skipped:", err.message));

if (process.env.NODE_ENV !== "test" && !process.env.VITEST) {
  server.listen(PORT, HOST, () => {
    log(`SafeAlert API running on ${HOST}:${PORT}`);
  });
}

module.exports = { app, server, io };

