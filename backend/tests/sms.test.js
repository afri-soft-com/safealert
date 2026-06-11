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
});
