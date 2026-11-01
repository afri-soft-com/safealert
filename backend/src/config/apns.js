/**
 * Direct APNs HTTP/2 sender (bypasses Firebase APNs key upload).
 * Required for iOS pushes when the app is killed and FCM has no APNs auth
 * key configured on the Firebase project.
 *
 * Env: APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_P8 (or APNS_KEY_PATH),
 *      APNS_BUNDLE_ID (default com.kakiranya.safealert),
 *      APNS_PRODUCTION (default true → api.push.apple.com).
 */
const fs = require("fs");
const http2 = require("http2");
const crypto = require("crypto");
const { log, warn, error: logError } = require("../utils/logger");

// Keep in sync with firebase.js (avoid circular require).
const SOS_PUSH_TYPES = new Set([
  "sos_alert",
  "nearby_alert",
  "group_sos",
  "group_report",
  "sector_sos",
  "trust_zone_alert",
  "safety_ping_ask",
  "safety_ping_missed",
]);
// Prefer .wav (also seeded into Library/Sounds at runtime). .caf remains in the IPA as fallback.
// Closed-app iOS: custom .wav/.caf kept failing silently on devices even when
// bundled. Use system "default" so killed-state alerts are audible (mute off).
// Override with SOS_IOS_SOUND / DEFAULT_IOS_SOUND env if needed.
const SOS_SOUND_IOS = (process.env.SOS_IOS_SOUND || "default").trim() || "default";
const DEFAULT_SOUND_IOS =
  (process.env.DEFAULT_IOS_SOUND || "default").trim() || "default";
// Keep in sync with firebase.js channel naming for docs only (APNs has no channels).

let cachedJwt = null;
let cachedJwtExp = 0;
let configured = null;

const bundleId = () =>
  process.env.APNS_BUNDLE_ID || process.env.IOS_BUNDLE_ID || "com.kakiranya.safealert";

const isProduction = () => {
  const v = (process.env.APNS_PRODUCTION || "true").toLowerCase();
  return v !== "0" && v !== "false" && v !== "no";
};

const loadP8 = () => {
  const raw = process.env.APNS_KEY_P8 || process.env.APNS_PRIVATE_KEY;
  if (raw && raw.includes("BEGIN")) {
    return raw.replace(/\\n/g, "\n");
  }
  const path = process.env.APNS_KEY_PATH;
  if (path && fs.existsSync(path)) {
    return fs.readFileSync(path, "utf8");
  }
  return null;
};

const isApnsConfigured = () => {
  if (configured != null) return configured;
  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID || process.env.IOS_TEAM_ID;
  const p8 = loadP8();
  configured = Boolean(keyId && teamId && p8);
  if (configured) {
    log(
      `APNs direct push ready (team=${teamId} key=${keyId} host=${
        isProduction() ? "production" : "sandbox"
      })`
    );
  } else {
    warn(
      "APNs not configured — iOS killed-state push needs APNS_KEY_ID / APNS_TEAM_ID / APNS_KEY_P8"
    );
  }
  return configured;
};

const b64url = (buf) =>
  Buffer.from(buf)
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");

const getApnsJwt = () => {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && cachedJwtExp - 60 > now) return cachedJwt;

  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID || process.env.IOS_TEAM_ID;
  const p8 = loadP8();
  const header = b64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = b64url(JSON.stringify({ iss: teamId, iat: now }));
  const unsigned = `${header}.${claims}`;
  const keyObj = crypto.createPrivateKey(p8);
  const sig = crypto.sign("sha256", Buffer.from(unsigned), {
    key: keyObj,
    dsaEncoding: "ieee-p1363",
  });
  cachedJwt = `${unsigned}.${b64url(sig)}`;
  cachedJwtExp = now + 3500;
  return cachedJwt;
};

const stringifyData = (data) => {
  if (!data || typeof data !== "object") return {};
  const out = {};
  for (const [k, v] of Object.entries(data)) {
    if (v === undefined || v === null) continue;
    out[k] = String(v);
  }
  return out;
};

/** Keep APNs under 4KB — large custom data silently kills killed-state delivery. */
const APNS_DATA_KEYS = [
  "type",
  "incidentId",
  "userId",
  "groupId",
  "lat",
  "lng",
  "zone_name",
  "origin",
  "pseudo",
  "phone",
  "title",
  "body",
  "zoneId",
  "zoneLabel",
  "incidentType",
];

const pickApnsData = (data) => {
  const out = {};
  for (const k of APNS_DATA_KEYS) {
    if (data[k] != null && data[k] !== "") out[k] = String(data[k]).slice(0, 200);
  }
  return out;
};

const buildApsBody = (payload) => {
  const data = stringifyData({
    ...(payload.data || {}),
    title: payload.notification?.title || payload.data?.title,
    body: payload.notification?.body || payload.data?.body,
  });
  const isSos = data?.type && SOS_PUSH_TYPES.has(data.type);
  const title = payload.notification?.title || data.title || "SafeAlert";
  const body = payload.notification?.body || data.body || "";
  return {
    aps: {
      alert: {
        title: String(title).slice(0, 100),
        body: String(body).slice(0, 200),
      },
      sound: isSos ? SOS_SOUND_IOS : DEFAULT_SOUND_IOS,
      badge: 1,
      "interruption-level": isSos ? "time-sensitive" : "active",
    },
    ...pickApnsData(data),
  };
};

const collapseIdFor = (payload) => {
  const data = payload?.data || {};
  const id =
    data.incidentId ||
    data.groupId ||
    `${data.type || "safealert"}-${Date.now()}`;
  return String(id).slice(0, 64);
};

const sendApnsToHost = (deviceToken, apsBody, production, collapseId) =>
  new Promise((resolve) => {
    const host = production
      ? "api.push.apple.com"
      : "api.sandbox.push.apple.com";
    let settled = false;
    let client;
    const finish = (val) => {
      if (settled) return;
      settled = true;
      try {
        client.close();
      } catch (_) {
        /* ignore */
      }
      resolve(val);
    };

    try {
      client = http2.connect(`https://${host}`);
    } catch (e) {
      logError("APNs connect error:", e.message);
      resolve({ ok: false, status: 0, reason: e.message, host });
      return;
    }

    client.on("error", (e) => {
      logError("APNs session error:", e.message);
      finish({ ok: false, status: 0, reason: e.message, host });
    });

    const headers = {
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${getApnsJwt()}`,
      "apns-topic": bundleId(),
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + 3600),
      "content-type": "application/json",
    };
    if (collapseId) headers["apns-collapse-id"] = collapseId;
    const req = client.request(headers);

    let status = 0;
    let resp = "";
    req.setEncoding("utf8");
    req.on("response", (headers) => {
      status = Number(headers[":status"] || 0);
    });
    req.on("data", (chunk) => {
      resp += chunk;
    });
    req.on("end", () => {
      let reason = "";
      try {
        reason = JSON.parse(resp || "{}").reason || "";
      } catch (_) {
        reason = resp.slice(0, 120);
      }
      if (status >= 200 && status < 300) {
        finish({ ok: true, status, reason: "", host });
        return;
      }
      logError("APNs send failed:", host, status, resp.slice(0, 300));
      finish({ ok: false, status, reason, host });
    });
    req.on("error", (e) => {
      logError("APNs request error:", e.message);
      finish({ ok: false, status: 0, reason: e.message, host });
    });
    req.end(JSON.stringify(apsBody));
  });

/**
 * @param {string} deviceToken hex APNs device token
 * @param {{ notification?: {title?:string,body?:string}, data?: object }} payload
 * @returns {Promise<string|null>} id on success, null on failure
 */
const sendApns = async (deviceToken, payload) => {
  if (!isApnsConfigured()) return null;
  const token = String(deviceToken || "")
    .trim()
    .replace(/\s/g, "");
  if (!token || token.length < 32) return null;

  const apsBody = buildApsBody(payload);
  const collapseId = collapseIdFor(payload);

  // TestFlight = production host; Xcode debug = sandbox. Race both so a wrong
  // APNS_PRODUCTION flag cannot blackhole killed-state alerts.
  const [prod, sand] = await Promise.all([
    sendApnsToHost(token, apsBody, true, collapseId),
    sendApnsToHost(token, apsBody, false, collapseId),
  ]);
  if (prod.ok) return `apns:production:${prod.status}`;
  if (sand.ok) {
    warn(`APNs delivered via sandbox (production failed: ${prod.reason || prod.status})`);
    return `apns:sandbox:${sand.status}`;
  }
  logError(
    "APNs both hosts failed:",
    `prod=${prod.reason || prod.status}`,
    `sand=${sand.reason || sand.status}`
  );
  return null;
};

module.exports = {
  isApnsConfigured,
  sendApns,
  bundleId,
};
