/**
 * Create (if needed) the iOS Firebase app on safealert-be940 and write
 * frontend/ios/Runner/GoogleService-Info.plist from the Management API.
 *
 * Usage:
 *   node backend/scripts/fetch-ios-firebase-config.js [path-to-service-account.json]
 */
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const PROJECT = "safealert-be940";
const BUNDLE_ID = "com.kakiranya.safealert";
const OUT = path.join(
  __dirname,
  "../../frontend/ios/Runner/GoogleService-Info.plist"
);
const saPath =
  process.argv[2] ||
  path.join(
    process.env.USERPROFILE || "",
    "Downloads",
    "safealert-be940-firebase-adminsdk-fbsvc-121d419c71.json"
  );

const sa = JSON.parse(fs.readFileSync(saPath, "utf8"));

function b64url(input) {
  return Buffer.from(input)
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

async function getAccessToken() {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(
    JSON.stringify({
      iss: sa.client_email,
      scope:
        "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/firebase",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })
  );
  const unsigned = `${header}.${claim}`;
  const sig = crypto.createSign("RSA-SHA256").update(unsigned).sign(sa.private_key);
  const jwt = `${unsigned}.${b64url(sig)}`;
  const body =
    "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=" +
    jwt;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  const json = await res.json();
  if (!json.access_token) {
    throw new Error("token failed: " + JSON.stringify(json));
  }
  return json.access_token;
}

async function api(token, method, apiPath, body) {
  const res = await fetch("https://firebase.googleapis.com/v1beta1/" + apiPath, {
    method,
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    data = text;
  }
  return { status: res.status, data };
}

async function waitOperation(token, opName) {
  // opName: projects/.../operations/...
  for (let i = 0; i < 30; i++) {
    const op = await api(token, "GET", opName);
    if (op.data.done) return op.data;
    await new Promise((r) => setTimeout(r, 1500));
  }
  throw new Error("operation timeout: " + opName);
}

async function main() {
  const token = await getAccessToken();
  let listed = await api(token, "GET", `projects/${PROJECT}/iosApps`);
  console.log("list status", listed.status);
  let apps = listed.data.apps || [];
  let app = apps.find((a) => a.bundleId === BUNDLE_ID);

  if (!app) {
    console.log("Creating iOS app", BUNDLE_ID);
    const created = await api(token, "POST", `projects/${PROJECT}/iosApps`, {
      bundleId: BUNDLE_ID,
      displayName: "SafeAlert iOS",
    });
    console.log("create status", created.status, JSON.stringify(created.data));
    if (created.status >= 400) {
      throw new Error("create failed");
    }
    if (created.data.name && String(created.data.name).includes("operations")) {
      const done = await waitOperation(token, created.data.name);
      console.log("op done", JSON.stringify(done.response || done));
    }
    // Refresh list
    for (let i = 0; i < 10 && !app; i++) {
      await new Promise((r) => setTimeout(r, 1000));
      listed = await api(token, "GET", `projects/${PROJECT}/iosApps`);
      apps = listed.data.apps || [];
      app = apps.find((a) => a.bundleId === BUNDLE_ID);
    }
  }

  if (!app) {
    throw new Error("iOS app still missing after create");
  }
  console.log("using app", app.name, app.appId);

  const cfg = await api(token, "GET", `${app.name}/config`);
  if (cfg.status >= 400 || !cfg.data.configFileContents) {
    throw new Error("config failed: " + JSON.stringify(cfg.data));
  }
  const plist = Buffer.from(cfg.data.configFileContents, "base64").toString(
    "utf8"
  );
  fs.writeFileSync(OUT, plist);
  console.log("Wrote", OUT);
  console.log(plist);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
