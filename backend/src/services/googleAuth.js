/**
 * Google ID token verification for SafeAlert (not SENGA JWT/roles).
 * PIN is the local second factor — no email OTP unless SMTP/Resend is added later.
 */
const { OAuth2Client } = require("google-auth-library");

const allowedAudiences = () => {
  const ids = [
    process.env.GOOGLE_CLIENT_ID,
    ...(String(process.env.GOOGLE_ANDROID_CLIENT_ID || "").split(",")),
    process.env.GOOGLE_IOS_CLIENT_ID,
  ]
    .map((s) => String(s || "").trim())
    .filter(Boolean);
  return [...new Set(ids)];
};

const errorWithCode = (code, message) => {
  const err = new Error(message || code);
  err.code = code;
  return err;
};

const defaultVerifyGoogleIdToken = async (idToken) => {
  const allowed = allowedAudiences();
  if (allowed.length === 0) {
    throw errorWithCode("not_configured", "GOOGLE_CLIENT_ID manquant");
  }
  const token = String(idToken || "").trim();
  if (!token) {
    throw errorWithCode("invalid_token", "idToken requis");
  }

  let payload;
  try {
    const client = new OAuth2Client();
    const ticket = await client.verifyIdToken({ idToken: token, audience: allowed });
    payload = ticket.getPayload() || {};
  } catch (err) {
    const msg = String(err && err.message ? err.message : err);
    if (/audience|aud/i.test(msg)) {
      throw errorWithCode("bad_aud", "Audience Google invalide");
    }
    throw errorWithCode("invalid_token", "Jeton Google invalide");
  }

  if (!payload.sub) {
    throw errorWithCode("invalid_token", "Jeton Google incomplet");
  }
  if (payload.aud && !allowed.includes(payload.aud)) {
    throw errorWithCode("bad_aud", "Audience Google invalide");
  }
  if (payload.email && payload.email_verified === false) {
    throw errorWithCode("unverified_email", "E-mail Google non vérifié");
  }
  return payload;
};

let verifyImpl = defaultVerifyGoogleIdToken;

const verifyGoogleIdToken = (idToken) => verifyImpl(idToken);

/** Test helper — restore with setGoogleIdTokenVerifier() (no args). */
const setGoogleIdTokenVerifier = (fn) => {
  verifyImpl = typeof fn === "function" ? fn : defaultVerifyGoogleIdToken;
};

module.exports = {
  allowedAudiences,
  verifyGoogleIdToken,
  setGoogleIdTokenVerifier,
  defaultVerifyGoogleIdToken,
};
