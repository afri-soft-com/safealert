const premiumPayments = require("../services/premiumPayments");
const { warn } = require("../utils/logger");

/**
 * POST /webhooks/afrisoft-payments
 * Requires req.rawBody (set by express.json verify) for HMAC.
 */
const afrisoftPayments = async (req, res) => {
  const rawBody =
    typeof req.rawBody === "string"
      ? req.rawBody
      : Buffer.isBuffer(req.rawBody)
        ? req.rawBody.toString("utf8")
        : JSON.stringify(req.body || {});

  const timestamp = req.get("X-AfriSoft-Timestamp") || "";
  const signature = req.get("X-AfriSoft-Signature") || "";
  const path =
    req.originalUrl?.split("?")[0] || req.path || "/webhooks/afrisoft-payments";

  try {
    const result = await premiumPayments.processWebhook({
      rawBody,
      timestamp,
      signature,
      path,
    });
    if (!result.ok && result.code === "invalid_signature") {
      warn("AfriSoft pay webhook invalid signature");
      return res.status(401).json({ error: "Invalid signature" });
    }
    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error("AfriSoft pay webhook error:", err.message);
    return res.status(500).json({ error: "Webhook processing failed" });
  }
};

module.exports = {
  afrisoftPayments,
  afrisoftPaymentsWebhook: afrisoftPayments,
};
