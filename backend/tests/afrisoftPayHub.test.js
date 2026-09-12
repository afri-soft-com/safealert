const crypto = require("crypto");

describe("afrisoftPayHub", () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    vi.resetModules();
    process.env = { ...originalEnv };
    process.env.AFRISOFT_PAY_HUB_URL = "https://pay.afri-soft.com";
    process.env.AFRISOFT_PAY_HUB_APP_ID = "safealert";
    process.env.AFRISOFT_PAY_HUB_API_KEY = "test-pay-secret";
    process.env.AFRISOFT_PAY_HUB_WEBHOOK_SECRET = "test-pay-secret";
    process.env.AFRISOFT_HUB_APP_ID = "afrisoft-partenaire";
    process.env.AFRISOFT_HUB_API_KEY = "sms-key-should-not-be-used";
    process.env.USD_TO_CDF_RATE = "2850";
  });

  afterEach(() => {
    process.env = originalEnv;
    vi.restoreAllMocks();
  });

  it("uses pay-specific app id, not SMS hub app id", () => {
    const hub = require("../src/services/afrisoftPayHub");
    expect(hub.appId()).toBe("safealert");
    expect(hub.isConfigured()).toBe(true);
  });

  it("normalizes RDC phones and operators", () => {
    const hub = require("../src/services/afrisoftPayHub");
    expect(hub.normalizeHubPhone("0970123456")).toBe("243970123456");
    expect(hub.normalizeHubPhone("+243970123456")).toBe("243970123456");
    expect(hub.normalizeTelecom("mpesa")).toBe("MP");
    expect(hub.normalizeTelecom("airtel")).toBe("AM");
    expect(hub.normalizeTelecom("OM")).toBe("OM");
  });

  it("applies CDF floor max(2300, ceil(usd * rate))", () => {
    const { toCdf, pricingWithCdf } = require("../src/services/premiumEntitlements");
    expect(toCdf(2)).toBe(5700);
    expect(toCdf(20)).toBe(57000);
    expect(toCdf(0.5)).toBe(2300);
    const p = pricingWithCdf();
    expect(p.monthly_cdf).toBe(5700);
    expect(p.yearly_cdf).toBe(57000);
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
