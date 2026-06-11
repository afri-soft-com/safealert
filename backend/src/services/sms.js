const { log, warn, error: logError } = require("../utils/logger");

let twilioClient = null;
let africasTalkingConfigured = false;

const initSMS = () => {
  if (process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN) {
    twilioClient = require("twilio")(
      process.env.TWILIO_ACCOUNT_SID,
      process.env.TWILIO_AUTH_TOKEN
    );
    log("Twilio SMS initialized");
  } else {
    warn("Twilio not configured — trying Africa's Talking or console fallback");
  }

  if (process.env.AFRICASTALKING_API_KEY && process.env.AFRICASTALKING_USERNAME) {
    africasTalkingConfigured = true;
    log("Africa's Talking SMS initialized");
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
  const twilioResult = await sendViaTwilio(to, body);
  if (twilioResult) return twilioResult;

  const atResult = await sendViaAfricasTalking(to, body);
  if (atResult) return atResult;

  log(`[SMS simulated] To: ${to}, Body: ${body}`);
  return { simulated: true };
};

const isSMSConfigured = () => Boolean(twilioClient || africasTalkingConfigured);

module.exports = { initSMS, sendSMS, isSMSConfigured, sendViaTwilio, sendViaAfricasTalking };
