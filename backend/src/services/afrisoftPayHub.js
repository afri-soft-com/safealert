/**
 * AfriSoft Payment Hub client (pay.afri-soft.com) — HMAC C2B / B2C.
 * Call only from the backend. Never expose keys to mobile clients.
 */
const crypto = require("crypto");
const { warn, error: logError } = require("../utils/logger");

const MIN_CDF = 2300;
const TELECOMS = new Set(["MP", "AM", "OM", "AF"]);

const baseUrl = () =>
  (
    process.env.AFRISOFT_PAY_HUB_URL ||
    process.env.PAY_HUB_URL ||
    process.env.AFRISOFT_PAY_BASE_URL ||
    "https://pay.afri-soft.com"
  )
    .trim()
    .replace(/\/$/, "");

/** Prefer pay-specific app id so SMS can keep afrisoft-partenaire. */
const appId = () =>
  (
    process.env.AFRISOFT_PAY_HUB_APP_ID ||
    process.env.AFRISOFT_PAY_HUB_APPID ||
    ""
  )
    .trim()
    .toLowerCase();

const apiKey = () =>
  (
    process.env.AFRISOFT_PAY_HUB_API_KEY ||
    process.env.AFRISOFT_HUB_API_KEY ||
    ""
  ).trim();

const webhookSecret = () =>
  (
    process.env.AFRISOFT_PAY_HUB_WEBHOOK_SECRET ||
    process.env.AFRISOFT_HUB_WEBHOOK_SECRET ||
    apiKey()
  ).trim();

const isConfigured = () => Boolean(appId() && apiKey());
/** Alias used by premiumEntitlements / older call sites. */
const hubConfigured = isConfigured;

const sign = (secret, ts, method, path, rawBody) =>
  crypto
    .createHmac("sha256", secret)
    .update(`${ts}.${method.toUpperCase()}.${path}.${rawBody || ""}`)
    .digest("hex");

const timingSafeEqualHex = (a, b) => {
  const aa = Buffer.from(String(a || "").trim().toLowerCase());
  const bb = Buffer.from(String(b || "").trim().toLowerCase());
  if (aa.length !== bb.length || aa.length === 0) return false;
  return crypto.timingSafeEqual(aa, bb);
};

/** Normalize to 243XXXXXXXXX (no +). */
const normalizeHubPhone = (raw) => {
  let digits = String(raw || "").replace(/\D/g, "");
  if (digits.startsWith("0") && digits.length === 10) {
    digits = `243${digits.slice(1)}`;
  } else if (digits.length === 9) {
    digits = `243${digits}`;
  }
  if (!/^243\d{9}$/.test(digits)) {
    const err = new Error("Numéro Mobile Money invalide (format RDC +243).");
    err.status = 400;
    err.code = "INVALID_PHONE";
    throw err;
  }
  return digits;
};

const normalizeTelecom = (raw) => {
  const t = String(raw || "")
    .trim()
    .toUpperCase()
    .replace(/[\s_-]+/g, "");
  const aliases = {
    MPESA: "MP",
    MP: "MP",
    AIRTEL: "AM",
    AIRTELMONEY: "AM",
    AM: "AM",
    ORANGE: "OM",
    ORANGEMONEY: "OM",
    OM: "OM",
    AFRIMONEY: "AF",
    AF: "AF",
  };
  const code = aliases[t] || t;
  if (!TELECOMS.has(code)) {
    const err = new Error(
      "Choisissez M-Pesa (MP), Airtel Money (AM) ou Orange Money (OM)."
    );
    err.status = 400;
    err.code = "INVALID_TELECOM";
    throw err;
  }
  return code;
};

/** Map UX operator ids (mpesa/airtel/orange) → hub telecom. */
const operatorToTelecom = (op) => {
  const s = String(op || "")
    .trim()
    .toLowerCase();
  if (s === "mpesa" || s === "mp") return "MP";
  if (s === "airtel" || s === "airtelmoney" || s === "am") return "AM";
  if (s === "orange" || s === "orangemoney" || s === "om") return "OM";
  return normalizeTelecom(op);
};

const tryReadErrorMessage = (data) => {
  if (!data || typeof data !== "object") return null;
  if (data.error && typeof data.error === "object" && data.error.message) {
    return String(data.error.message);
  }
  if (data.message) return String(data.message);
  return null;
};

async function sendSigned(method, path, bodyObj) {
  if (!isConfigured()) {
    const err = new Error("Hub AfriSoft paiements non configuré.");
    err.status = 503;
    err.code = "PAY_HUB_NOT_CONFIGURED";
    throw err;
  }
  const rawBody = method === "GET" ? "" : JSON.stringify(bodyObj);
  const ts = String(Math.floor(Date.now() / 1000));
  const key = apiKey();
  const sig = sign(key, ts, method, path, rawBody);
  const res = await fetch(`${baseUrl()}${path}`, {
    method,
    headers: {
      ...(method !== "GET" ? { "Content-Type": "application/json" } : {}),
      "X-AfriSoft-App-Id": appId(),
      "X-AfriSoft-Api-Key": key,
      "X-AfriSoft-Timestamp": ts,
      "X-AfriSoft-Signature": sig,
    },
    body: method === "GET" ? undefined : rawBody,
  });
  const data = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, data };
}

async function createPayment({
  amountCdf,
  phone,
  telecom,
  reference,
  purpose = "pay",
  idempotencyKey,
  metadata,
}) {
  const amount = Math.round(Number(amountCdf));
  if (!Number.isFinite(amount) || amount < MIN_CDF) {
    const err = new Error(`Montant minimum Mobile Money : ${MIN_CDF} FC.`);
    err.status = 400;
    err.code = "AMOUNT_TOO_LOW";
    throw err;
  }
  const body = {
    app_id: appId(),
    amount_cdf: amount,
    currency: "CDF",
    phone: normalizeHubPhone(phone),
    telecom: normalizeTelecom(telecom),
    reference,
    purpose: purpose || "pay",
    idempotency_key: idempotencyKey,
  };
  if (metadata && typeof metadata === "object") body.metadata = metadata;

  const { ok, status, data } = await sendSigned("POST", "/v1/payments", body);
  if (!ok) {
    warn(
      "Pay hub POST /v1/payments failed",
      status,
      tryReadErrorMessage(data) || ""
    );
    return {
      ok: false,
      status: "FAILED",
      payment_id: null,
      reference,
      provider_ref: null,
      amount_cdf: amount,
      telecom: body.telecom,
      message: null,
      payment_url: null,
      error:
        tryReadErrorMessage(data) ||
        "Impossible de démarrer le paiement Mobile Money.",
      http_status: status,
    };
  }
  return {
    ok: true,
    status: data.status || "PENDING",
    payment_id: data.payment_id || null,
    reference: data.reference || reference,
    provider_ref: data.provider_ref || null,
    amount_cdf: data.amount_cdf ?? amount,
    telecom: data.telecom || body.telecom,
    message:
      data.message || "Confirmez le paiement sur votre téléphone Mobile Money.",
    payment_url: data.payment_url || data.paymentUrl || null,
    error: null,
    http_status: status,
  };
}

async function createPayout({
  amountCdf,
  phone,
  telecom,
  reference,
  idempotencyKey,
}) {
  const amount = Math.round(Number(amountCdf));
  if (!Number.isFinite(amount) || amount < MIN_CDF) {
    const err = new Error(`Retrait minimum : ${MIN_CDF} FC.`);
    err.status = 400;
    err.code = "AMOUNT_TOO_LOW";
    throw err;
  }
  const body = {
    app_id: appId(),
    amount_cdf: amount,
    currency: "CDF",
    phone: normalizeHubPhone(phone),
    telecom: normalizeTelecom(telecom),
    reference,
    purpose: "withdraw",
    idempotency_key: idempotencyKey,
  };
  const { ok, status, data } = await sendSigned("POST", "/v1/payouts", body);
  if (!ok) {
    warn(
      "Pay hub POST /v1/payouts failed",
      status,
      tryReadErrorMessage(data) || ""
    );
    return {
      ok: false,
      status: "FAILED",
      payment_id: null,
      reference,
      provider_ref: null,
      amount_cdf: amount,
      telecom: body.telecom,
      message: null,
      error: tryReadErrorMessage(data) || "Échec du retrait Mobile Money.",
      http_status: status,
    };
  }
  return {
    ok: true,
    status: data.status || "PENDING",
    payment_id: data.payment_id || null,
    reference: data.reference || reference,
    provider_ref: data.provider_ref || null,
    amount_cdf: data.amount_cdf ?? amount,
    telecom: data.telecom || body.telecom,
    message: data.message || null,
    error: null,
    http_status: status,
  };
}

async function getPayment(paymentId) {
  if (!paymentId) return null;
  const path = `/v1/payments/${encodeURIComponent(String(paymentId).trim())}`;
  const { ok, data } = await sendSigned("GET", path, null);
  if (!ok) {
    logError("Pay hub GET payment failed", paymentId);
    return null;
  }
  return data;
}

function verifyIncomingWebhook(timestamp, signatureHex, path, rawBody) {
  if (!isConfigured()) return false;
  if (!timestamp || !signatureHex) return false;
  const ts = Number(timestamp);
  if (!Number.isFinite(ts)) return false;
  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - ts) > 300) return false;

  const secret = webhookSecret();
  const cleanPath =
    String(path || "").split("?")[0] || "/webhooks/afrisoft-payments";
  const publicPath = cleanPath.startsWith("/api/v1/")
    ? cleanPath.slice(4)
    : cleanPath;

  const candidates = [publicPath, cleanPath, "/webhooks/afrisoft-payments"];
  const body = rawBody == null ? "" : String(rawBody);
  for (const p of candidates) {
    const expected = sign(secret, String(timestamp), "POST", p, body);
    if (timingSafeEqualHex(signatureHex, expected)) return true;
  }
  return false;
}

module.exports = {
  MIN_CDF,
  TELECOMS,
  isConfigured,
  hubConfigured,
  appId,
  baseUrl,
  normalizeHubPhone,
  normalizeTelecom,
  operatorToTelecom,
  createPayment,
  createPayout,
  getPayment,
  verifyIncomingWebhook,
  sign,
};
