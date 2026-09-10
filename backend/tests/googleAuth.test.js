const request = require("supertest");
const path = require("path");
const jwt = require("jsonwebtoken");

const mockQuery = vi.fn();
const mockRelease = vi.fn();
const mockClient = { query: mockQuery, release: mockRelease };
const mockConnect = vi.fn();
const mockOn = vi.fn();
const mockPool = { query: mockQuery, connect: mockConnect, on: mockOn };

const dbPath = path.resolve(__dirname, "../src/config/database.js");
require.cache[dbPath] = {
  exports: { pool: mockPool },
};

process.env.JWT_SECRET = "test-secret-google-auth-32chars!!";
process.env.JWT_EXPIRES_IN = "1h";
process.env.GOOGLE_CLIENT_ID = "test-web.apps.googleusercontent.com";
process.env.GOOGLE_ANDROID_CLIENT_ID = "android-a.apps.googleusercontent.com, android-b.apps.googleusercontent.com";
process.env.NODE_ENV = "test";

const {
  allowedAudiences,
  setGoogleIdTokenVerifier,
  defaultVerifyGoogleIdToken,
} = require("../src/services/googleAuth");
const { app } = require("../src/server");

const existingUser = {
  id: "user-google-1",
  phone: "+243811234567",
  email: "ada@example.com",
  google_id: "sub-existing",
  pseudo: "Ada",
  role: "citizen",
  sector_name: null,
  is_discreet_mode: false,
  share_presence: true,
  sos_notify_groups: true,
};

beforeEach(() => {
  mockQuery.mockReset();
  mockQuery.mockResolvedValue({ rows: [] });
  mockConnect.mockResolvedValue(mockClient);
  mockRelease.mockReset();
  setGoogleIdTokenVerifier();
});

afterEach(() => {
  setGoogleIdTokenVerifier();
});

describe("allowedAudiences", () => {
  it("includes web and CSV Android client IDs", () => {
    const aud = allowedAudiences();
    expect(aud).toContain("test-web.apps.googleusercontent.com");
    expect(aud).toContain("android-a.apps.googleusercontent.com");
    expect(aud).toContain("android-b.apps.googleusercontent.com");
  });
});

describe("POST /api/auth/google", () => {
  it("logs in an existing user matched by google_id", async () => {
    setGoogleIdTokenVerifier(async () => ({
      sub: "sub-existing",
      email: "ada@example.com",
      email_verified: true,
      aud: "test-web.apps.googleusercontent.com",
      name: "Ada Lovelace",
    }));
    mockQuery.mockImplementation(async (sql) => {
      const q = String(sql);
      if (q.includes("google_id")) return { rows: [existingUser] };
      return { rows: [] };
    });

    const res = await request(app).post("/api/auth/google").send({ idToken: "valid-id-token" });
    expect(res.status).toBe(200);
    expect(res.body.token).toBeTruthy();
    expect(res.body.isNew).toBe(false);
    expect(res.body.needsPinSetup).toBe(true);
    expect(res.body.user.id).toBe("user-google-1");
    expect(res.body.user.pseudo).toBe("Ada");
    expect(res.body.user.role).toBe("citizen");
    const decoded = jwt.verify(res.body.token, process.env.JWT_SECRET);
    expect(decoded.userId).toBe("user-google-1");
    expect(decoded.role).toBe("citizen");
  });

  it("creates a citizen user when Google account is new", async () => {
    setGoogleIdTokenVerifier(async () => ({
      sub: "sub-new",
      email: "new@example.com",
      email_verified: true,
      aud: "test-web.apps.googleusercontent.com",
      name: "Pat Citoyen",
    }));
    mockQuery.mockImplementation(async (sql, params) => {
      const q = String(sql);
      if (q.includes("INSERT INTO users")) {
        return {
          rows: [
            {
              id: "user-new",
              phone: null,
              email: params[1],
              google_id: params[2],
              pseudo: params[0],
              role: "citizen",
              sector_name: null,
              is_discreet_mode: false,
              share_presence: true,
              sos_notify_groups: true,
            },
          ],
        };
      }
      return { rows: [] };
    });

    const res = await request(app).post("/api/auth/google").send({ idToken: "new-id-token" });
    expect(res.status).toBe(200);
    expect(res.body.isNew).toBe(true);
    expect(res.body.user.role).toBe("citizen");
    expect(res.body.user.phone).toBeNull();
    expect(res.body.user.pseudo).toBe("Pat Citoyen");
    expect(res.body.needsPinSetup).toBe(true);
  });

  it("rejects a token with a bad audience", async () => {
    setGoogleIdTokenVerifier(async () => {
      const err = new Error("bad_aud");
      err.code = "bad_aud";
      throw err;
    });
    const res = await request(app).post("/api/auth/google").send({ idToken: "bad-aud-token" });
    expect(res.status).toBe(401);
    expect(res.body.code).toBe("bad_aud");
    expect(res.body.error).toMatch(/non autorisé/i);
    expect(res.body.token).toBeUndefined();
  });

  it("rejects an unverified email", async () => {
    setGoogleIdTokenVerifier(async () => {
      const err = new Error("unverified_email");
      err.code = "unverified_email";
      throw err;
    });
    const res = await request(app).post("/api/auth/google").send({ idToken: "unverified-token" });
    expect(res.status).toBe(401);
    expect(res.body.code).toBe("unverified_email");
    expect(res.body.error).toMatch(/n'est pas vérifiée/i);
  });

  it("never promotes a new Google user to platform_admin", async () => {
    process.env.PLATFORM_ADMIN_PHONE = "+243971163574";
    setGoogleIdTokenVerifier(async () => ({
      sub: "sub-admin-attempt",
      email: "admin@example.com",
      email_verified: true,
      aud: "test-web.apps.googleusercontent.com",
      name: "Admin",
    }));
    mockQuery.mockImplementation(async (sql, params) => {
      const q = String(sql);
      if (q.includes("INSERT INTO users")) {
        expect(params[2]).toBe("sub-admin-attempt");
        return {
          rows: [
            {
              id: "user-citizen",
              phone: null,
              email: "admin@example.com",
              google_id: "sub-admin-attempt",
              pseudo: "Admin",
              role: "citizen",
            },
          ],
        };
      }
      if (q.includes("role = 'platform_admin'")) {
        throw new Error("must not promote via Google");
      }
      return { rows: [] };
    });

    const res = await request(app).post("/api/auth/google").send({ idToken: "tok" });
    expect(res.status).toBe(200);
    expect(res.body.user.role).toBe("citizen");
    delete process.env.PLATFORM_ADMIN_PHONE;
  });
});

describe("defaultVerifyGoogleIdToken", () => {
  it("maps unverified email on a signed payload", async () => {
    const { OAuth2Client } = require("google-auth-library");
    const spy = vi.spyOn(OAuth2Client.prototype, "verifyIdToken").mockResolvedValue({
      getPayload: () => ({
        sub: "sub-1",
        email: "x@y.z",
        email_verified: false,
        aud: "test-web.apps.googleusercontent.com",
      }),
    });
    await expect(defaultVerifyGoogleIdToken("tok")).rejects.toMatchObject({ code: "unverified_email" });
    spy.mockRestore();
  });

  it("maps audience mismatch", async () => {
    const { OAuth2Client } = require("google-auth-library");
    const spy = vi.spyOn(OAuth2Client.prototype, "verifyIdToken").mockResolvedValue({
      getPayload: () => ({
        sub: "sub-1",
        email: "x@y.z",
        email_verified: true,
        aud: "other-app.apps.googleusercontent.com",
      }),
    });
    await expect(defaultVerifyGoogleIdToken("tok")).rejects.toMatchObject({ code: "bad_aud" });
    spy.mockRestore();
  });
});
