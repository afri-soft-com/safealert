require("dotenv").config();

// Bootstraps HTTP + Socket.IO; CI deploy waits on /health/ready after Render goes live.
const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const http = require("http");
const { Server } = require("socket.io");
const { apiLimiter } = require("./middleware/rateLimit");
const { maintenanceGate } = require("./middleware/maintenance");
const { pool } = require("./config/database");
const { initFCM, isFcmConfigured } = require("./config/firebase");
const { initSMS, isSMSConfigured } = require("./services/sms");
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
const paymentsRoutes = require("./routes/payments");
const webhooksRoutes = require("./routes/webhooks");
const opsRoutes = require("./routes/ops");
const invitesRoutes = require("./routes/invites");
const safetyPingsRoutes = require("./routes/safetyPings");
const corridorsRoutes = require("./routes/corridors");
const publicRoutes = require("./routes/public");
const legalRoutes = require("./routes/legal");
const incidentTypesRoutes = require("./routes/incidentTypes");
const appRoutes = require("./routes/app");
const liveCirclesRoutes = require("./routes/liveCircles");

const app = express();
const server = http.createServer(app);

const path = require("path");
const fs = require("fs");

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
app.use(
  express.json({
    verify: (req, _res, buf) => {
      // Preserve raw body for AfriSoft hub webhook HMAC verification.
      if (req.originalUrl && req.originalUrl.startsWith("/webhooks/")) {
        req.rawBody = buf.toString("utf8");
      }
    },
  })
);
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
    fcm: isFcmConfigured() ? "up" : "down",
    sms: isSMSConfigured() ? "up" : "down",
    payHub: (() => {
      try {
        return require("./services/afrisoftPayHub").isConfigured() ? "up" : "down";
      } catch (_) {
        return "down";
      }
    })(),
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
      fcm: isFcmConfigured() ? "ok" : "missing",
      sms: isSMSConfigured() ? "ok" : "missing",
    });
  } catch (err) {
    console.error("Readiness check failed:", err.message);
    return res.status(503).json({ status: "not_ready" });
  }
});

app.use(maintenanceGate);

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
app.use("/api/payments", paymentsRoutes);
app.use("/webhooks", webhooksRoutes);
app.use("/api/ops", opsRoutes);
app.use("/api/invites", invitesRoutes);
app.use("/api/safety-pings", safetyPingsRoutes);
app.use("/api/corridors", corridorsRoutes);
app.use("/api/public", publicRoutes);
app.use("/api/legal", legalRoutes);
app.use("/api/incident-types", incidentTypesRoutes);
app.use("/api/app", appRoutes);
app.use("/api/live-circles", liveCirclesRoutes);

// Ephemeral public trip follow page (short token, read-only map)
const followTripHtml = path.join(__dirname, "public", "follow-trip.html");
app.get("/t/:token", (req, res) => {
  if (!fs.existsSync(followTripHtml)) {
    return res.status(404).send("Page indisponible");
  }
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.sendFile(followTripHtml);
});

const followSosHtml = path.join(__dirname, "public", "follow-sos.html");
app.get("/s/:token", (req, res) => {
  if (!fs.existsSync(followSosHtml)) {
    return res.status(404).send("Page indisponible");
  }
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.sendFile(followSosHtml);
});

// Deep-link landing for circle invites (opens app or shows code)
app.get("/invite/:code", (req, res) => {
  const code = String(req.params.code || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.send(`<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Invitation SafeAlert</title><style>body{font-family:system-ui;padding:24px;background:#f4f7f7;color:#123}a{color:#0B6E6E}</style></head>
<body><h1>SafeAlert</h1><p>Code d'invitation au cercle de confiance :</p>
<p style="font-size:1.6rem;font-weight:700;letter-spacing:0.1em">${code}</p>
<p>Ouvrez l'application SafeAlert → Confiance → « Rejoindre avec un code ».</p>
<p><a href="safealert://invite/${code}">Ouvrir dans l'app</a></p></body></html>`);
});

// HTTPS landing for group invite QR (phone cameras need https://, not safealert://)
const joinGroupHtml = path.join(__dirname, "public", "join-group.html");
const sendJoinGroupPage = (req, res) => {
  if (!fs.existsSync(joinGroupHtml)) {
    return res.status(404).type("html").send(
      "<!DOCTYPE html><html lang=\"fr\"><body style=\"font-family:system-ui;padding:24px\"><h1>SafeAlert</h1><p>Page d'invitation indisponible. Ouvrez l'app → Groupes → Rejoindre.</p></body></html>"
    );
  }
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  return res.sendFile(joinGroupHtml);
};

app.get(["/g", "/g/"], sendJoinGroupPage);
app.get("/g/:code", sendJoinGroupPage);
app.get("/group/:code", (req, res) => {
  const code = String(req.params.code || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (!code) return res.redirect(302, "/g");
  return res.redirect(302, `/g/${encodeURIComponent(code)}`);
});
// Legacy / mistaken QR that kept `/api` in the origin (Safari showed JSON 404).
app.get(["/api/g", "/api/g/", "/api/g/:code"], (req, res) => {
  const code = String(req.params.code || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  return res.redirect(302, code ? `/g/${encodeURIComponent(code)}` : "/g");
});
app.get(["/api/group/:code"], (req, res) => {
  const code = String(req.params.code || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  return res.redirect(302, code ? `/g/${encodeURIComponent(code)}` : "/g");
});

// Friendly root (camera / bookmarks hitting the API host alone).
app.get("/", (req, res) => {
  res
    .status(200)
    .type("html")
    .send(`<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>SafeAlert</title><style>body{font-family:system-ui;padding:28px;background:#f4f7f7;color:#123;max-width:480px;margin:0 auto}a{color:#0B6E6E;font-weight:700}</style></head>
<body><h1>SafeAlert</h1>
<p>Application de sécurité citoyenne.</p>
<p>Pour rejoindre un <strong>groupe de voisins</strong>, scannez le QR d'invitation (lien <code>/g/CODE</code>) ou ouvrez l'app → Groupes → Rejoindre.</p>
<p><a href="safealert://">Ouvrir SafeAlert</a></p>
</body></html>`);
});

// Universal Links / App Links metadata (best-effort; Team ID via env).
app.get("/.well-known/apple-app-site-association", (req, res) => {
  const teamId = (process.env.APPLE_TEAM_ID || "").trim();
  const bundleId = (process.env.IOS_BUNDLE_ID || "com.kakiranya.safealert").trim();
  const appID = teamId ? `${teamId}.${bundleId}` : bundleId;
  res.setHeader("Content-Type", "application/json");
  res.json({
    applinks: {
      apps: [],
      details: [
        {
          appID,
          paths: ["/g/*", "/group/*", "/invite/*", "/t/*", "/s/*"],
        },
      ],
    },
  });
});
app.get("/.well-known/assetlinks.json", (req, res) => {
  const pkg = (process.env.ANDROID_PACKAGE_NAME || "com.safealert.safealert").trim();
  const fingerprints = String(process.env.ANDROID_SHA256_CERT_FINGERPRINTS || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  res.setHeader("Content-Type", "application/json");
  if (fingerprints.length === 0) return res.json([]);
  res.json([
    {
      relation: ["delegate_permission/common.handle_all_urls"],
      target: {
        namespace: "android_app",
        package_name: pkg,
        sha256_cert_fingerprints: fingerprints,
      },
    },
  ]);
});

const adminWebDist = process.env.ADMIN_WEB_DIST;
if (adminWebDist) {
  const adminPath = path.resolve(adminWebDist);
  app.use("/admin", express.static(adminPath));
  app.get("/admin/*", (req, res) => {
    res.sendFile(path.join(adminPath, "index.html"));
  });
}

app.use((req, res) => {
  const accept = String(req.headers.accept || "");
  if (accept.includes("text/html")) {
    return res.status(404).type("html").send(`<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Page introuvable — SafeAlert</title><style>body{font-family:system-ui;padding:28px;background:#f4f7f7;color:#123;max-width:480px;margin:0 auto}a{color:#0B6E6E}</style></head>
<body><h1>Lien invalide</h1>
<p>Cette adresse SafeAlert n'existe pas. Si vous voulez rejoindre un groupe, demandez un nouveau QR (lien <code>…/g/CODE</code>) ou saisissez le code dans l'app → Groupes → Rejoindre.</p>
<p><a href="/">Accueil SafeAlert</a> · <a href="safealert://">Ouvrir l'app</a></p>
</body></html>`);
  }
  res.status(404).json({ error: "Page introuvable." });
});

app.use((err, req, res, next) => {
  console.error("Unhandled error:", err);
  const status = err.status || err.statusCode || 500;
  const message =
    status < 500 && err.message && err.message.length < 160
      ? err.message
      : "Une erreur est survenue. Réessayez.";
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
  const { processSafetyPings } = require("./controllers/safetyPingController");

  // Overdue safe trips — every 60s
  setInterval(() => {
    processOverdueTrips().catch((err) => warn("trip overdue job:", err.message));
  }, 60_000);

  // Safety pings « Tu es OK ? » — every 60s
  setInterval(() => {
    processSafetyPings().catch((err) => warn("safety ping job:", err.message));
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
