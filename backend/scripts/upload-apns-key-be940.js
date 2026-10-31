/**
 * Upload an APNs .p8 auth key to Firebase project safealert-be940 (FCM Apple config).
 *
 * Usage:
 *   node backend/scripts/upload-apns-key-be940.js <AuthKey_XXXX.p8> <KEY_ID> <TEAM_ID> [serviceAccount.json]
 */
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const PROJECT = "safealert-be940";
const p8Path = process.argv[2];
const keyId = process.argv[3];
const teamId = process.argv[4];
const saPath =
  process.argv[5] ||
  path.join(
    process.env.USERPROFILE || "",
    "Downloads",
    "safealert-be940-firebase-adminsdk-fbsvc-121d419c71.json"
  );

if (!p8Path || !keyId || !teamId) {
  console.error(
    "Usage: node upload-apns-key-be940.js <AuthKey.p8> <KEY_ID> <TEAM_ID>"
  );
  process.exit(1);
}

const sa = JSON.parse(fs.readFileSync(saPath, "utf8"));
const p8 = fs.readFileSync(p8Path, "utf8");

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
  if (!json.access_token) throw new Error(JSON.stringify(json));
  return json.access_token;
}

async function main() {
  const token = await getAccessToken();
  // Firebase App Management — set APNs auth key at project level via FCM API.
  // Endpoint used by Firebase Console (Apple app configuration):
  const url = `https://firebase.googleapis.com/v1beta1/projects/${PROJECT}/apnsAuthKeys`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      keyId,
      teamId,
      privateKey: p8,
    }),
  });
  const text = await res.text();
  console.log("POST apnsAuthKeys", res.status, text);

  // Fallback: legacy patch on iosApps if project-level fails
  if (res.status >= 400) {
    const list = await fetch(
      `https://firebase.googleapis.com/v1beta1/projects/${PROJECT}/iosApps`,
      { headers: { Authorization: "Bearer " + token } }
    );
    const listed = await list.json();
    const app = (listed.apps || []).find(
      (a) => a.bundleId === "com.kakiranya.safealert"
    );
    if (!app) {
      throw new Error("iOS app missing; cannot attach APNs key");
    }
    const urls = [
      `https://firebase.googleapis.com/v1beta1/${app.name}:setApnsAuthKey`,
      `https://firebase.googleapis.com/v1beta1/${app.name}/apnsAuthKey`,
      `https://fcm.googleapis.com/v1/projects/${PROJECT}/apnsAuthKeys`,
    ];
    for (const u of urls) {
      const r = await fetch(u, {
        method: "POST",
        headers: {
          Authorization: "Bearer " + token,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          keyId,
          teamId,
          privateKey: p8,
          name: keyId,
        }),
      });
      const t = await r.text();
      console.log(u, r.status, t.slice(0, 500));
      if (r.status < 400) return;
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
