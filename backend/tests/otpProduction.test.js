const request = require("supertest");
const path = require("path");

const mockQuery = vi.fn();
const dbPath = path.resolve(__dirname, "../src/config/database.js");
require.cache[dbPath] = {
  exports: { pool: { query: mockQuery, connect: vi.fn(), on: vi.fn() } },
};

// SMS provider configured but failing.
const smsPath = path.resolve(__dirname, "../src/services/sms.js");
require.cache[smsPath] = {
  id: smsPath,
  filename: smsPath,
  loaded: true,
  exports: {
    sendSMS: vi.fn().mockRejectedValue(new Error("hub down")),
    isSMSConfigured: () => true,
    initSMS: () => {},
  },
};

process.env.JWT_SECRET = "test-secret";
const { app } = require("../src/server");

describe("request-code when the SMS fails", () => {
  let prevEnv;
  beforeEach(() => {
    mockQuery.mockReset();
    mockQuery.mockResolvedValue({ rows: [] });
    prevEnv = process.env.NODE_ENV;
  });
  afterEach(() => {
    process.env.NODE_ENV = prevEnv;
  });

  it("never returns the code in production", async () => {
    process.env.NODE_ENV = "production";
    const res = await request(app)
      .post("/api/auth/request-code")
      .send({ phone: "+243811234567" });
    expect(res.status).toBe(503);
    expect(res.body.devCode).toBeUndefined();
    expect(res.body.codeOtp).toBeUndefined();
  });

  it("still shows the code outside production for local testing", async () => {
    process.env.NODE_ENV = "test";
    const res = await request(app)
      .post("/api/auth/request-code")
      .send({ phone: "+243811234568" });
    expect(res.status).toBe(200);
    expect(res.body.devCode).toMatch(/^\d{6}$/);
  });
});
