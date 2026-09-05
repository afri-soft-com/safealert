const crypto = require("crypto");
const { log, warn, error: logError } = require("../utils/logger");

let twilioClient = null;
let africasTalkingConfigured = false;
let serdipayConfigured = false;
let afrisoftHubConfigured = false;

/**
 * Priorité d'envoi SMS :
 * 1. Hub AfriSoft (AFRISOFT_HUB_API_KEY + AFRISOFT_HUB_APP_ID) — OTP RDC
 * 2. SerdiPay direct
 * 3. Twilio
 * 4. Africa's Talking
 * 5. Simulation console
 */
const hubBaseUrl = () =>
  (process.env.AFRISOFT_SMS_HUB_URL || process.env.SMS_HUB_URL || "https://sms.afri-soft.com")
    .trim()
    .replace(/\/$/, "");

const hubAppId = () => (process.env.AFRISOFT_HUB_APP_ID || "").trim();
const hubApiKey = () => (process.env.AFRISOFT_HUB_API_KEY || "").trim();

const normalizeHubPhone = (to) => {
  let p = String(to || "").replace(/\s/g, "");
  if (p.startsWith("+")) p = p.slice(1);
  if (/^0\d{9}$/.test(p)) p = `243${p.slice(1)}`;
  return p;
};

const initSMS = () => {
  afrisoftHubConfigured = Boolean(hubAppId() && hubApiKey());
  if (afrisoftHubConfigured) {
    log("AfriSoft SMS hub initialized");
  }

  if (process.env.SERDIPAY_API_KEY && process.env.SERDIPAY_SMS_URL) {
    serdipayConfigured = true;
    log("SerdiPay SMS initialized");
  } else if (process.env.SERDIPAY_API_KEY && !process.env.SERDIPAY_SMS_URL) {
    warn("SERDIPAY_API_KEY présent mais SERDIPAY_SMS_URL manquant — SerdiPay ignoré");
  }

  if (process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN) {
    twilioClient = require("twilio")(
      process.env.TWILIO_ACCOUNT_SID,
      process.env.TWILIO_AUTH_TOKEN
    );
    log("Twilio SMS initialized");
  }

  if (process.env.AFRICASTALKING_API_KEY && process.env.AFRICASTALKING_USERNAME) {
    africasTalkingConfigured = true;
    log("Africa's Talking SMS initialized");
  }

  if (!afrisoftHubConfigured && !serdipayConfigured && !twilioClient && !africasTalkingConfigured) {
    warn("Aucun fournisseur SMS configuré — fallback simulation console");
  }
};

const sendViaAfriSoftHub = async (to, body) => {
  if (!afrisoftHubConfigured) return null;
  const appId = hubAppId();
  const apiKey = hubApiKey();
  const path = "/v1/sms/send";
  const phone = normalizeHubPhone(to);
  const text = String(body || "").slice(0, 640);
  const purpose = /\b\d{6}\b/.test(text) ? "otp" : "notify";
  const rawBody = JSON.stringify({
    app_id: appId,
    phone,
    text,
    reference: `${appId}_${purpose}_${crypto.randomUUID()}`,
    idempotency_key: `${appId}:${purpose}:${phone}:${crypto
      .createHash("sha256")
      .update(text)
      .digest("hex")
      .slice(0, 16)}`,
  });
  const ts = String(Math.floor(Date.now() / 1000));
  const sig = crypto
    .createHmac("sha256", apiKey)
    .update(`${ts}.POST.${path}.${rawBody}`)
    .digest("hex");

  try {
    const res = await fetch(`${hubBaseUrl()}${path}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-AfriSoft-App-Id": appId,
        "X-AfriSoft-Api-Key": apiKey,
        "X-AfriSoft-Timestamp": ts,
        "X-AfriSoft-Signature": sig,
      },
      body: rawBody,
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      logError("AfriSoft SMS hub error:", res.status, data.code || data.message || "");
      return null;
    }
    return { transport: "afrisoft", ...data };
  } catch (err) {
    logError("AfriSoft SMS hub error:", err.message);
    return null;
  }
};

const sendViaSerdiPay = async (to, body) => {
  if (!serdipayConfigured) return null;
  try {
    const url = process.env.SERDIPAY_SMS_URL;
    const payload = {
      to,
      phone: to,
      message: body,
      body,
      sender: process.env.SERDIPAY_SENDER_ID || "SafeAlert",
    };

    const headers = {
      "Content-Type": "application/json",
      Accept: "application/json",
      Authorization: `Bearer ${process.env.SERDIPAY_API_KEY}`,
    };
    if (process.env.SERDIPAY_API_KEY_HEADER === "apiKey") {
      delete headers.Authorization;
      headers.apiKey = process.env.SERDIPAY_API_KEY;
    }

    const res = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
    });

    const text = await res.text();
    let data;
    try {
      data = text ? JSON.parse(text) : {};
    } catch {
      data = { raw: text };
    }

    if (!res.ok) {
      logError("SerdiPay SMS error:", res.status, data);
      return null;
    }
    return { provider: "serdipay", ...data };
  } catch (err) {
    logError("SerdiPay SMS error:", err.message);
    return null;
  }
};

const sendViaTwilio = async (to, body) => {
  if (!twilioClient) return null;
  try {
    return await twilioClient.messages.create({
      body,
      to,
      from: process.env.TWILIO_PHONE_NUMBER,
    });
  } catch (err) {
    logError("Twilio SMS error:", err.message);
    return null;
  }
};

const sendViaAfricasTalking = async (to, body) => {
  if (!africasTalkingConfigured) return null;
  try {
    const params = new URLSearchParams();
    params.append("username", process.env.AFRICASTALKING_USERNAME);
    params.append("to", to);
    params.append("message", body);

    const res = await fetch("https://api.africastalking.com/version1/messaging", {
      method: "POST",
      headers: {
        apiKey: process.env.AFRICASTALKING_API_KEY,
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      },
      body: params.toString(),
    });

    const data = await res.json();
    if (!res.ok) {
      console.error("Africa's Talking SMS error:", data);
      return null;
    }
    return data;
  } catch (err) {
    logError("Africa's Talking SMS error:", err.message);
    return null;
  }
};

const sendSMS = async (to, body) => {
  const preferred = (process.env.SMS_PROVIDER || "auto").toLowerCase();

  const tryHub = async () => sendViaAfriSoftHub(to, body);
  const trySerdi = async () => sendViaSerdiPay(to, body);
  const tryTwilio = async () => sendViaTwilio(to, body);
  const tryAt = async () => sendViaAfricasTalking(to, body);

  if (preferred === "afrisoft" || preferred === "afrisofthub") {
    const r = await tryHub();
    if (r) return r;
  } else if (preferred === "serdipay") {
    const r = await trySerdi();
    if (r) return r;
  } else if (preferred === "twilio") {
    const r = await tryTwilio();
    if (r) return r;
  } else if (preferred === "africastalking") {
    const r = await tryAt();
    if (r) return r;
  } else {
    const hub = await tryHub();
    if (hub) return hub;
    const serdi = await trySerdi();
    if (serdi) return serdi;
    const twilioResult = await tryTwilio();
    if (twilioResult) return twilioResult;
    const atResult = await tryAt();
    if (atResult) return atResult;
  }

  log(`[SMS simulated] To: ${to}, Body: ${body}`);
  return { simulated: true };
};

const isSMSConfigured = () =>
  Boolean(afrisoftHubConfigured || serdipayConfigured || twilioClient || africasTalkingConfigured);

module.exports = {
  initSMS,
  sendSMS,
  isSMSConfigured,
  sendViaAfriSoftHub,
  sendViaSerdiPay,
  sendViaTwilio,
  sendViaAfricasTalking,
  normalizeHubPhone,
};
