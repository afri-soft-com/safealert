describe("SMS service", () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    vi.resetModules();
    process.env = { ...originalEnv };
    delete process.env.TWILIO_ACCOUNT_SID;
    delete process.env.TWILIO_AUTH_TOKEN;
    delete process.env.TWILIO_PHONE_NUMBER;
    delete process.env.AFRICASTALKING_API_KEY;
    delete process.env.AFRICASTALKING_USERNAME;
    delete process.env.SERDIPAY_API_KEY;
    delete process.env.SERDIPAY_SMS_URL;
    delete process.env.AFRISOFT_HUB_APP_ID;
    delete process.env.AFRISOFT_HUB_API_KEY;
    delete process.env.AFRISOFT_SMS_HUB_URL;
    delete process.env.SMS_HUB_URL;
    delete process.env.SMS_PROVIDER;
  });

  afterEach(() => {
    process.env = originalEnv;
    vi.restoreAllMocks();
  });

  it("simulates SMS when no provider is configured", async () => {
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const { initSMS, sendSMS, isSMSConfigured } = require("../src/services/sms");

    initSMS();
    expect(isSMSConfigured()).toBe(false);

    const result = await sendSMS("+243811111111", "Test message");
    expect(result.simulated).toBe(true);
    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("[SMS simulated]"));

    logSpy.mockRestore();
  });

  it("marks configured when Africa's Talking env vars are set", async () => {
    process.env.AFRICASTALKING_API_KEY = "test-key";
    process.env.AFRICASTALKING_USERNAME = "sandbox";

    const { initSMS, isSMSConfigured } = require("../src/services/sms");
    initSMS();
    expect(isSMSConfigured()).toBe(true);
  });

  it("Africa's Talking send returns null on HTTP error", async () => {
    process.env.AFRICASTALKING_API_KEY = "test-key";
    process.env.AFRICASTALKING_USERNAME = "sandbox";

    global.fetch = vi.fn().mockResolvedValue({
      ok: false,
      json: async () => ({ error: "Invalid" }),
    });

    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const { initSMS, sendViaAfricasTalking } = require("../src/services/sms");
    initSMS();

    const result = await sendViaAfricasTalking("+243811111111", "Hello");
    expect(result).toBeNull();

    logSpy.mockRestore();
  });

  it("marks configured when AfriSoft hub env vars are set", () => {
    process.env.AFRISOFT_HUB_APP_ID = "afrisoft-partenaire";
    process.env.AFRISOFT_HUB_API_KEY = "test-secret";

    const { initSMS, isSMSConfigured } = require("../src/services/sms");
    initSMS();
    expect(isSMSConfigured()).toBe(true);
  });

  it("normalizes DRC phones for the hub", () => {
    const { normalizeHubPhone } = require("../src/services/sms");
    expect(normalizeHubPhone("+243811111111")).toBe("243811111111");
    expect(normalizeHubPhone("243811111111")).toBe("243811111111");
    expect(normalizeHubPhone("0811111111")).toBe("243811111111");
  });

  it("sends OTP text via AfriSoft hub with HMAC headers", async () => {
    process.env.AFRISOFT_HUB_APP_ID = "afrisoft-partenaire";
    process.env.AFRISOFT_HUB_API_KEY = "test-secret";
    process.env.AFRISOFT_SMS_HUB_URL = "https://sms.example.test";

    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ sms_id: "sms_1", status: "SENT", provider: "serdipay" }),
    });

    const crypto = require("crypto");
    const { initSMS, sendSMS } = require("../src/services/sms");
    initSMS();

    const result = await sendSMS("+243811111111", "Votre code SafeAlert: 123456. Valide 5 minutes.");
    expect(result.transport).toBe("afrisoft");
    expect(result.status).toBe("SENT");
    expect(result.sms_id).toBe("sms_1");
    expect(global.fetch).toHaveBeenCalledTimes(1);

    const [url, opts] = global.fetch.mock.calls[0];
    expect(url).toBe("https://sms.example.test/v1/sms/send");
    expect(opts.method).toBe("POST");
    expect(opts.headers["X-AfriSoft-App-Id"]).toBe("afrisoft-partenaire");
    expect(opts.headers["X-AfriSoft-Api-Key"]).toBe("test-secret");

    const body = JSON.parse(opts.body);
    expect(body.app_id).toBe("afrisoft-partenaire");
    expect(body.phone).toBe("243811111111");
    expect(body.text).toContain("123456");
    expect(body.reference).toMatch(/^afrisoft-partenaire_otp_/);
    expect(body.idempotency_key).toMatch(/^afrisoft-partenaire:otp:243811111111:/);

    const ts = opts.headers["X-AfriSoft-Timestamp"];
    const expectedSig = crypto
      .createHmac("sha256", "test-secret")
      .update(`${ts}.POST./v1/sms/send.${opts.body}`)
      .digest("hex");
    expect(opts.headers["X-AfriSoft-Signature"]).toBe(expectedSig);
  });

  it("falls back to simulation when the hub returns an HTTP error", async () => {
    process.env.AFRISOFT_HUB_APP_ID = "afrisoft-partenaire";
    process.env.AFRISOFT_HUB_API_KEY = "test-secret";

    global.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 401,
      json: async () => ({ code: "HUB_AUTH_INVALID_KEY" }),
    });

    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const { initSMS, sendSMS } = require("../src/services/sms");
    initSMS();

    const result = await sendSMS("+243811111111", "Test message");
    expect(result.simulated).toBe(true);
    logSpy.mockRestore();
  });
});
