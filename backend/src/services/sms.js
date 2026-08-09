const { log, warn, error: logError } = require("../utils/logger");

let twilioClient = null;
let africasTalkingConfigured = false;
let serdipayConfigured = false;

/**
 * Priorité d'envoi SMS :
 * 1. SerdiPay (si SERDIPAY_API_KEY + SERDIPAY_SMS_URL) — OTP RDC cible
 * 2. Twilio
 * 3. Africa's Talking
 * 4. Simulation console (dev uniquement utile)
 *
 * L'API SMS SerdiPay n'est pas encore publique ; l'URL et le format
 * se configurent via env dès réception des clés / doc partenaire.
 */
const initSMS = () => {
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

  if (!serdipayConfigured && !twilioClient && !africasTalkingConfigured) {
    warn("Aucun fournisseur SMS configuré — fallback simulation console");
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

  const trySerdi = async () => sendViaSerdiPay(to, body);
  const tryTwilio = async () => sendViaTwilio(to, body);
  const tryAt = async () => sendViaAfricasTalking(to, body);

  if (preferred === "serdipay") {
    const r = await trySerdi();
    if (r) return r;
  } else if (preferred === "twilio") {
    const r = await tryTwilio();
    if (r) return r;
  } else if (preferred === "africastalking") {
    const r = await tryAt();
    if (r) return r;
  } else {
    // auto : SerdiPay → Twilio → Africa's Talking
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
  Boolean(serdipayConfigured || twilioClient || africasTalkingConfigured);

module.exports = {
  initSMS,
  sendSMS,
  isSMSConfigured,
  sendViaSerdiPay,
  sendViaTwilio,
  sendViaAfricasTalking,
};
