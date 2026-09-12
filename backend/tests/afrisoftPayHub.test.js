const crypto = require("crypto");
const { describe, it, expect, beforeEach } = require("vitest");

describe("afrisoftPayHub", () => {
  beforeEach(() => {
    process.env.AFRISOFT_PAY_HUB_URL = "https://pay.afri-soft.com";
    process.env.AFRISOFT_PAY_HUB_APP_ID = "safealert";
    process.env.AFRISOFT_PAY_HUB_API_KEY = "test-pay-secret";
    process.env.AFRISOFT_PAY_HUB_WEBHOOK_SECRET = "test-pay-secret";
    process.env.AFRISOFT_HUB_APP_ID = "afrisoft-partenaire";
    process.env.AFRISOFT_HUB_API_KEY = "sms-key-should-not-be-used";
  });

  it("uses pay-specific app id, not SMS hub app id", () => {
    // Fresh require after env set — module reads env at call time
    const hub = require("../src/services/afrisoftPayHub");
    expect(hub.appId()).toBe("safealert");
    expect(hub.isConfigured()).toBe(true);
    expect(hub.hubConfigured()).toBe(true);
  });

  it("normalizes RDC phones and operators", () => {
    const hub = require("../src/services/afrisoftPayHub");
    expect(hub.normalizeHubPhone("0970123456")).toBe("243970123456");
    expect(hub.normalizeHubPhone("+243970123456")).toBe("243970123456");
    expect(hub.operatorToTelecom("mpesa")).toBe("MP");
    expect(hub.operatorToTelecom("airtel")).toBe("AM");
    expect(hub.normalizeTelecom("OM")).toBe("OM");
  });

  it("verifies webhook HMAC for /webhooks/afrisoft-payments", () => {
    const hub = require("../src/services/afrisoftPayHub");
    const raw = JSON.stringify({
      event: "payment.completed",
      status: "COMPLETED",
      payment_id: "pay_test",
      amount_cdf: 5700,
    });
    const ts = String(Math.floor(Date.now() / 1000));
    const path = "/webhooks/afrisoft-payments";
    const sig = crypto
      .createHmac("sha256", "test-pay-secret")
      .update(`${ts}.POST.${path}.${raw}`)
      .digest("hex");
    expect(hub.verifyIncomingWebhook(ts, sig, path, raw)).toBe(true);
    expect(hub.verifyIncomingWebhook(ts, "deadbeef", path, raw)).toBe(false);
  });
});
