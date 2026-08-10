const crypto = require("crypto");
const { pool } = require("../config/database");
const { partnerWebhooks } = require("../config/features");
const { warn, error: logError } = require("../utils/logger");

const deliverEvent = async (eventType, payload) => {
  if (!partnerWebhooks()) return { delivered: 0 };

  try {
    const partners = await pool.query(
      `SELECT id, webhook_url, webhook_secret, webhook_events
       FROM partner_api_keys
       WHERE is_active = true AND webhook_url IS NOT NULL`
    );

    let delivered = 0;
    for (const p of partners.rows) {
      const events = String(p.webhook_events || "sos,incident,cancel")
        .split(",")
        .map((e) => e.trim())
        .filter(Boolean);
      if (!events.includes(eventType) && !events.includes("*")) continue;

      const body = JSON.stringify({
        event: eventType,
        ts: new Date().toISOString(),
        data: payload,
      });
      const signature = p.webhook_secret
        ? crypto.createHmac("sha256", p.webhook_secret).update(body).digest("hex")
        : null;

      let status = "pending";
      let responseCode = null;
      try {
        const res = await fetch(p.webhook_url, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-SafeAlert-Event": eventType,
            ...(signature ? { "X-SafeAlert-Signature": signature } : {}),
          },
          body,
          signal: AbortSignal.timeout(8000),
        });
        responseCode = res.status;
        status = res.ok ? "delivered" : "failed";
        if (res.ok) delivered += 1;
      } catch (err) {
        status = "failed";
        warn("Partner webhook delivery failed:", p.id, err.message);
      }

      await pool.query(
        `INSERT INTO partner_webhook_deliveries
           (partner_id, event_type, payload, status, response_code, attempts, delivered_at)
         VALUES ($1, $2, $3::jsonb, $4, $5, 1, CASE WHEN $4 = 'delivered' THEN NOW() ELSE NULL END)`,
        [p.id, eventType, body, status, responseCode]
      );
    }
    return { delivered };
  } catch (err) {
    logError("partnerWebhooks error:", err.message);
    return { delivered: 0 };
  }
};

module.exports = { deliverEvent };
