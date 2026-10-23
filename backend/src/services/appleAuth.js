/**
 * Sign in with Apple — verify identityToken (App Store guideline 4.8 when Google is offered).
 */
const crypto = require("crypto");
const jwt = require("jsonwebtoken");

const errorWithCode = (code, message) => {
  const err = new Error(message || code);
  err.code = code;
  return err;
};

const allowedAudiences = () =>
  [
    ...String(process.env.APPLE_CLIENT_IDS || "").split(/[,\s]+/),
    ...String(process.env.APPLE_BUNDLE_ID || "").split(/[,\s]+/),
  ]
    .map((s) => String(s || "").trim())
    .filter(Boolean);

/** Synthetic +243 phone for Apple accounts without a linked number yet. */
const syntheticApplePhone = (appleId) => {
  const hex = crypto.createHash("sha256").update(`safealert-apple:${appleId}`).digest("hex");
  const digits = hex.replace(/\D/g, "0").padEnd(8, "0").slice(0, 8);
  return `+2438${digits}`;
};

let cacheJwks = null;

const fetchAppleJwks = async () => {
  const now = Date.now();
  if (cacheJwks && now - cacheJwks.fetchedAt < 60 * 60 * 1000) {
    return cacheJwks.keys;
  }
  const res = await fetch("https://appleid.apple.com/auth/keys", {
    signal: AbortSignal.timeout(15_000),
  });
  if (!res.ok) {
    throw errorWithCode("jwks_unavailable", "Impossible de joindre les clés Apple (JWKS)");
  }
  const json = await res.json().catch(() => ({}));
  const keys = Array.isArray(json.keys) ? json.keys : [];
  if (!keys.length) {
    throw errorWithCode("jwks_empty", "JWKS Apple vide");
  }
  cacheJwks = { fetchedAt: now, keys };
  return keys;
};

const jwkToPem = (jwk) => {
  const keyObject = crypto.createPublicKey({
    key: { kty: jwk.kty, n: jwk.n, e: jwk.e },
    format: "jwk",
  });
  return keyObject.export({ type: "spki", format: "pem" }).toString();
};

const defaultVerifyAppleIdentityToken = async (identityToken, displayName) => {
  const token = String(identityToken || "").trim();
  if (!token) {
    throw errorWithCode("invalid_token", "identityToken requis");
  }

  // Test / local simulation (never enable in real App Store builds without intent).
  if (
    (process.env.APPLE_AUTH_MODE === "simulation" || process.env.NODE_ENV === "test") &&
    token.startsWith("SIM-APPLE:")
  ) {
    const parts = token.split(":");
    const email = parts[1] || "demo.apple@safealert.app";
    const nom = parts.slice(2).join(":") || displayName || "Utilisateur Apple";
    return {
      appleId: `sim-${crypto.createHash("sha256").update(email).digest("hex").slice(0, 16)}`,
      email,
      name: nom,
    };
  }

  const audiences = allowedAudiences();
  if (audiences.length === 0) {
    throw errorWithCode(
      "not_configured",
      "APPLE_CLIENT_IDS non configuré (bundle ID, ex. com.kakiranya.safealert)"
    );
  }

  const decoded = jwt.decode(token, { complete: true });
  if (!decoded || typeof decoded === "string" || !decoded.header?.kid) {
    throw errorWithCode("invalid_token", "Token Apple invalide");
  }

  const keys = await fetchAppleJwks();
  const jwk = keys.find((k) => k.kid === decoded.header.kid);
  if (!jwk) {
    throw errorWithCode("unknown_kid", "Clé Apple inconnue (kid)");
  }

  let payload;
  try {
    payload = jwt.verify(token, jwkToPem(jwk), {
      algorithms: ["RS256"],
      issuer: "https://appleid.apple.com",
    });
  } catch {
    throw errorWithCode("invalid_token", "Token Apple invalide ou expiré");
  }

  const aud = payload.aud;
  const audOk = Array.isArray(aud)
    ? aud.some((a) => audiences.includes(String(a)))
    : audiences.includes(String(aud || ""));
  if (!audOk) {
    throw errorWithCode("bad_aud", "Token Apple : audience (bundle ID) non autorisée");
  }

  const appleId = typeof payload.sub === "string" ? payload.sub : "";
  if (!appleId) {
    throw errorWithCode("invalid_token", "Profil Apple incomplet (sub requis)");
  }

  const email =
    typeof payload.email === "string" && payload.email.trim()
      ? payload.email.trim().toLowerCase()
      : null;

  const name =
    (displayName && String(displayName).trim()) ||
    (email ? email.split("@")[0] : null) ||
    "Utilisateur Apple";

  return { appleId, email, name };
};

let verifyImpl = defaultVerifyAppleIdentityToken;

const verifyAppleIdentityToken = (identityToken, displayName) =>
  verifyImpl(identityToken, displayName);

/** Test helper — restore with setAppleIdentityTokenVerifier() (no args). */
const setAppleIdentityTokenVerifier = (fn) => {
  verifyImpl = typeof fn === "function" ? fn : defaultVerifyAppleIdentityToken;
};

module.exports = {
  allowedAudiences,
  syntheticApplePhone,
  verifyAppleIdentityToken,
  setAppleIdentityTokenVerifier,
  defaultVerifyAppleIdentityToken,
};
