const request = require("supertest");
const path = require("path");
const bcrypt = require("bcryptjs");

// Pre-populate Node's module cache so controllers get our mock pool
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

const jwt = require("jsonwebtoken");
process.env.JWT_SECRET = "test-secret";
process.env.JWT_EXPIRES_IN = "1h";

const { app } = require("../src/server");

const validToken = jwt.sign({ userId: "user-1", role: "citizen" }, process.env.JWT_SECRET);
const user2Token = jwt.sign({ userId: "user-2", role: "citizen" }, process.env.JWT_SECRET);
const leaderToken = jwt.sign({ userId: "leader-1", role: "leader" }, process.env.JWT_SECRET);
const adminToken = jwt.sign({ userId: "admin-1", role: "platform_admin" }, process.env.JWT_SECRET);

let validOtpHash;

beforeAll(async () => {
  validOtpHash = await bcrypt.hash("123456", 4);
});

beforeEach(() => {
  mockQuery.mockReset();
  mockQuery.mockResolvedValue({ rows: [] });
  mockConnect.mockResolvedValue(mockClient);
  mockRelease.mockReset();
  vi.stubGlobal(
    "fetch",
    vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ address: { suburb: "Gombe" } }),
    })
  );
});

describe("Health", () => {
  it("GET /health returns ok", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("ok");
  });

  it("GET /health/ready returns ready when DB responds", async () => {
    mockQuery.mockResolvedValueOnce({ rows: [{ "?column?": 1 }] });
    const res = await request(app).get("/health/ready");
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("ready");
    expect(res.body.db).toBe("ok");
  });

  it("GET /health/ready returns 503 when DB fails", async () => {
    mockQuery.mockRejectedValueOnce(new Error("connection refused"));
    const res = await request(app).get("/health/ready");
    expect(res.status).toBe(503);
    expect(res.body.status).toBe("not_ready");
  });
});

describe("Auth", () => {
  it("POST /api/auth/request-code returns code sent", async () => {
    mockQuery.mockResolvedValue({ rows: [] });
    const res = await request(app)
      .post("/api/auth/request-code")
      .send({ phone: "+243811234567" });
    expect(res.status).toBe(200);
    expect(res.body.message).toBe("Code envoyé");
    expect(res.body.expiresIn).toBe(300);
  }, 15000);

  it("POST /api/auth/request-code fails without phone", async () => {
    const res = await request(app).post("/api/auth/request-code").send({});
    expect(res.status).toBe(400);
  });

  it("POST /api/auth/verify-code creates user and returns JWT", async () => {
    mockQuery.mockReset();
    mockQuery
      .mockResolvedValueOnce({ rows: [{ id: "otp1", code_hash: validOtpHash }] })
      // SELECT user (not found)
      .mockResolvedValueOnce({ rows: [] })
      // UPDATE otp used
      .mockResolvedValueOnce({ rows: [] })
      // INSERT user
      .mockResolvedValueOnce({ rows: [{ id: "u1", phone: "+243811234567", pseudo: "Test", role: "citizen" }] });
    const res = await request(app)
      .post("/api/auth/verify-code")
      .send({ phone: "+243811234567", code: "123456", pseudo: "Test" });
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty("token");
  });

  it("POST /api/auth/verify-code rejects missing pseudo without consuming OTP", async () => {
    mockQuery.mockReset();
    mockQuery
      .mockResolvedValueOnce({ rows: [{ id: "otp1", code_hash: validOtpHash }] })
      .mockResolvedValueOnce({ rows: [] }); // SELECT user
    const res = await request(app)
      .post("/api/auth/verify-code")
      .send({ phone: "+243811234567", code: "123456" });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/pseudo requis/i);
    // No UPDATE otp_codes when pseudo missing
    expect(mockQuery).toHaveBeenCalledTimes(2);
  });

  it("POST /api/auth/verify-code rejects invalid OTP", async () => {
    mockQuery.mockReset();
    mockQuery.mockResolvedValueOnce({ rows: [{ id: "otp1", code_hash: validOtpHash }] });
    const res = await request(app)
      .post("/api/auth/verify-code")
      .send({ phone: "+243811234567", code: "000000" });
    expect(res.status).toBe(401);
    expect(res.body.error).toMatch(/invalide|expiré/i);
  });

  it("POST /api/auth/verify-code rejects missing OTP", async () => {
    mockQuery.mockReset();
    mockQuery.mockResolvedValueOnce({ rows: [] });
    const res = await request(app)
      .post("/api/auth/verify-code")
      .send({ phone: "+243811234567", code: "123456" });
    expect(res.status).toBe(401);
  });

  it("PUT /api/auth/position updates user location", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ share_presence: true }] })
      .mockResolvedValueOnce({ rows: [] });
    const res = await request(app)
      .put("/api/auth/position")
      .set("Authorization", `Bearer ${validToken}`)
      .send({ lat: -4.3, lng: 15.3 });
    expect(res.status).toBe(200);
    expect(res.body.message).toBe("Position mise à jour");
  });
});

describe("Annuaire", () => {
  it("GET /api/annuaire returns numbers", async () => {
    mockQuery.mockResolvedValue({
      rows: [{ id: "1", service_name: "Police", phone_number: "112", service_type: "police" }],
    });
    const res = await request(app).get("/api/annuaire");
    expect(res.status).toBe(200);
    expect(res.body[0].service_name).toBe("Police");
  });
});

describe("Incidents", () => {
  it("GET /api/map/incidents returns list", async () => {
    mockQuery.mockResolvedValue({
      rows: [{ id: "i1", incident_type: "agression", lat: -4.3, lng: 15.3, status: "active" }],
    });
    const res = await request(app).get("/api/map/incidents");
    expect(res.status).toBe(200);
    expect(res.body[0].incident_type).toBe("agression");
  });

  it("POST /api/map/incidents requires auth", async () => {
    const res = await request(app)
      .post("/api/map/incidents")
      .send({ lat: -4.3, lng: 15.3, incident_type: "vol" });
    expect(res.status).toBe(401);
  });

  it("POST /api/map/incidents/:id/verify rejects duplicate vote", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ verified_by: 1, status: "active" }] })
      .mockResolvedValueOnce({ rows: [{ id: "v1" }] });
    const res = await request(app)
      .post("/api/map/incidents/i1/verify")
      .set("Authorization", `Bearer ${validToken}`);
    expect(res.status).toBe(409);
    expect(res.body.error).toMatch(/déjà confirmé/i);
  });

  it("POST /api/map/incidents/:id/verify records vote and increments count", async () => {
    mockQuery
      .mockResolvedValueOnce({
        rows: [{ verified_by: 0, status: "active", severity: "vigilance", reliability_score: 50, user_id: "u1" }],
      })
      .mockResolvedValueOnce({ rows: [] }) // existing verification
      .mockResolvedValueOnce({ rows: [] }) // insert verification
      .mockResolvedValueOnce({ rows: [] }) // bump reporter score
      .mockResolvedValueOnce({ rows: [{ id: "i1", verified_by: 1, status: "active", severity: "vigilance" }] });
    const res = await request(app)
      .post("/api/map/incidents/i1/verify")
      .set("Authorization", `Bearer ${validToken}`);
    expect(res.status).toBe(200);
    expect(res.body.verified_by).toBe(1);
  });

  it("POST /api/map/incidents/:id/verify sets danger when 3 confirmations", async () => {
    mockQuery
      .mockResolvedValueOnce({
        rows: [{ verified_by: 2, status: "active", severity: "vigilance", reliability_score: 50, user_id: "u1" }],
      })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ id: "i1", verified_by: 3, status: "verified", severity: "danger" }] });
    const res = await request(app)
      .post("/api/map/incidents/i1/verify")
      .set("Authorization", `Bearer ${validToken}`);
    expect(res.status).toBe(200);
    expect(res.body.severity).toBe("danger");
    expect(res.body.status).toBe("verified");
  });
});

describe("Admin", () => {
  it("GET /api/admin/users rejects citizen", async () => {
    const res = await request(app)
      .get("/api/admin/users")
      .set("Authorization", `Bearer ${validToken}`);
    expect(res.status).toBe(403);
  });

  it("GET /api/admin/users allows platform_admin", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ total: 1 }] })
      .mockResolvedValueOnce({ rows: [{ id: "u1", phone: "+243811234567", role: "citizen" }] });
    const res = await request(app)
      .get("/api/admin/users")
      .set("Authorization", `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(1);
  });

  it("PATCH /api/admin/users/:id/role updates role", async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [{ id: "u2", phone: "+243811234568", pseudo: "Leader", role: "leader", sector_name: null }],
    });
    const res = await request(app)
      .patch("/api/admin/users/u2/role")
      .set("Authorization", `Bearer ${adminToken}`)
      .send({ role: "leader" });
    expect(res.status).toBe(200);
    expect(res.body.role).toBe("leader");
  });

  it("POST /api/partner/register rejects citizen", async () => {
    const res = await request(app)
      .post("/api/partner/register")
      .set("Authorization", `Bearer ${validToken}`)
      .send({ partner_name: "Test" });
    expect(res.status).toBe(403);
  });

  it("GET /api/admin/stats returns dashboard metrics", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ total: 10 }] })
      .mockResolvedValueOnce({ rows: [{ total: 50 }] })
      .mockResolvedValueOnce({ rows: [{ total: 5 }] })
      .mockResolvedValueOnce({ rows: [{ total: 2 }] })
      .mockResolvedValueOnce({ rows: [{ total: 3 }] });
    const res = await request(app)
      .get("/api/admin/stats")
      .set("Authorization", `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(res.body.users).toBe(10);
    expect(res.body.incidents).toBe(50);
  });

  it("GET /api/admin/emergency-numbers lists entries", async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [{ id: "e1", service_name: "Police", phone_number: "112" }],
    });
    const res = await request(app)
      .get("/api/admin/emergency-numbers")
      .set("Authorization", `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(1);
  });

  it("GET /api/admin/incidents returns paginated list", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ total: 1 }] })
      .mockResolvedValueOnce({
        rows: [{ id: "i1", incident_type: "vol", status: "active", zone_name: "Gombe" }],
      });
    const res = await request(app)
      .get("/api/admin/incidents")
      .set("Authorization", `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(1);
  });
});

describe("SOS", () => {
  it("POST /api/sos/trigger with auth creates alert", async () => {
    mockQuery.mockResolvedValue({ rows: [{ id: "sos1", incident_type: "sos", status: "active" }] });
    const res = await request(app)
      .post("/api/sos/trigger")
      .set("Authorization", `Bearer ${validToken}`)
      .send({ lat: -4.3, lng: 15.3 });
    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty("incident");
  });

  it("POST /api/sos/cancel cancels latest within window", async () => {
    mockQuery
      .mockResolvedValueOnce({
        rows: [{
          id: "sos1",
          status: "active",
          severity: "alert",
          created_at: new Date().toISOString(),
          lat: -4.3,
          lng: 15.3,
        }],
      })
      .mockResolvedValueOnce({ rows: [{ id: "sos1", status: "false_alarm" }] });
    const res = await request(app)
      .post("/api/sos/cancel")
      .set("Authorization", `Bearer ${validToken}`);
    expect(res.status).toBe(200);
    expect(res.body.message).toMatch(/fausse alerte|annul/i);
  });

  it("POST /api/sos/cancel rejects after 2-minute window", async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [{
        id: "sos1",
        status: "active",
        severity: "alert",
        created_at: new Date(Date.now() - 3 * 60 * 1000).toISOString(),
        lat: -4.3,
        lng: 15.3,
      }],
    });
    const res = await request(app)
      .post("/api/sos/cancel")
      .set("Authorization", `Bearer ${validToken}`);
    expect(res.status).toBe(403);
    expect(res.body.error).toMatch(/2 minutes/i);
  });
});

describe("Contacts", () => {
  it("GET /api/contacts requires auth", async () => {
    const res = await request(app).get("/api/contacts");
    expect(res.status).toBe(401);
  });

  it("GET /api/contacts with auth returns list", async () => {
    mockQuery.mockResolvedValue({ rows: [{ id: "c1", contact_name: "Marie" }] });
    const res = await request(app)
      .get("/api/contacts")
      .set("Authorization", `Bearer ${validToken}`);
    expect(res.status).toBe(200);
    expect(res.body[0].contact_name).toBe("Marie");
  });
});

describe("Leader", () => {
  it("GET /api/leader/sector/incidents rejects citizen", async () => {
    const res = await request(app)
      .get("/api/leader/sector/incidents")
      .set("Authorization", `Bearer ${validToken}`);
    expect(res.status).toBe(403);
  });

  it("GET /api/leader/sector/incidents allows leader", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ sector_name: null }] })
      .mockResolvedValueOnce({ rows: [] });
    const res = await request(app)
      .get("/api/leader/sector/incidents")
      .set("Authorization", `Bearer ${leaderToken}`);
    expect(res.status).toBe(200);
  });

  it("PUT /api/leader/sector/incidents/:id/acknowledge sets acknowledged", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ status: "active" }] })
      .mockResolvedValueOnce({ rows: [{ id: "i1", status: "acknowledged" }] });
    const res = await request(app)
      .put("/api/leader/sector/incidents/i1/acknowledge")
      .set("Authorization", `Bearer ${leaderToken}`);
    expect(res.status).toBe(200);
    expect(res.body.incident.status).toBe("acknowledged");
  });

  it("PUT /api/leader/sector/incidents/:id/acknowledge moves to in_progress", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ status: "acknowledged" }] })
      .mockResolvedValueOnce({ rows: [{ id: "i1", status: "in_progress" }] });
    const res = await request(app)
      .put("/api/leader/sector/incidents/i1/acknowledge")
      .set("Authorization", `Bearer ${leaderToken}`);
    expect(res.status).toBe(200);
    expect(res.body.incident.status).toBe("in_progress");
  });
});

describe("Groups join requests", () => {
  it("POST /api/groups/join creates pending request", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ id: "g1", name: "Voisins" }] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] });
    const res = await request(app)
      .post("/api/groups/join")
      .set("Authorization", `Bearer ${user2Token}`)
      .send({ invite_code: "ABCD1234" });
    expect(res.status).toBe(201);
    expect(res.body.message).toMatch(/demande envoyée/i);
    expect(res.body.status).toBe("pending");
  });

  it("POST /api/groups/join rejects duplicate pending request", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ id: "g1", name: "Voisins" }] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ id: "r1", status: "pending" }] });
    const res = await request(app)
      .post("/api/groups/join")
      .set("Authorization", `Bearer ${user2Token}`)
      .send({ invite_code: "ABCD1234" });
    expect(res.status).toBe(409);
    expect(res.body.error).toMatch(/déjà en attente/i);
  });

  it("GET /api/groups/:id/join-requests rejects non-admin", async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] });
    const res = await request(app)
      .get("/api/groups/g1/join-requests")
      .set("Authorization", `Bearer ${user2Token}`);
    expect(res.status).toBe(403);
  });

  it("GET /api/groups/:id/join-requests allows group admin", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ "?column?": 1 }] })
      .mockResolvedValueOnce({
        rows: [{ id: "r1", user_id: "user-2", pseudo: "Jean", phone: "+243811111111", status: "pending" }],
      });
    const res = await request(app)
      .get("/api/groups/g1/join-requests")
      .set("Authorization", `Bearer ${validToken}`);
    expect(res.status).toBe(200);
    expect(res.body[0].pseudo).toBe("Jean");
  });

  it("PUT /api/groups/join-requests/:id/approve adds member", async () => {
    mockQuery
      .mockResolvedValueOnce({
        rows: [{ id: "r1", group_id: "g1", user_id: "user-2", status: "pending", group_name: "Voisins" }],
      })
      .mockResolvedValueOnce({ rows: [{ "?column?": 1 }] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] });
    const res = await request(app)
      .put("/api/groups/join-requests/r1/approve")
      .set("Authorization", `Bearer ${validToken}`);
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("approved");
  });

  it("PUT /api/groups/join-requests/:id/reject updates status", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ id: "r1", group_id: "g1", user_id: "user-2", status: "pending" }] })
      .mockResolvedValueOnce({ rows: [{ "?column?": 1 }] })
      .mockResolvedValueOnce({ rows: [] });
    const res = await request(app)
      .put("/api/groups/join-requests/r1/reject")
      .set("Authorization", `Bearer ${validToken}`);
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("rejected");
  });

  it("POST /api/groups/:id/join creates request for public group", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ id: "g1", name: "Public", is_public: true }] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] });
    const res = await request(app)
      .post("/api/groups/g1/join")
      .set("Authorization", `Bearer ${user2Token}`)
      .send({});
    expect(res.status).toBe(201);
    expect(res.body.status).toBe("pending");
  });

  it("POST /api/groups/:id/join rejects private group", async () => {
    mockQuery.mockResolvedValueOnce({ rows: [{ id: "g1", name: "Privé", is_public: false }] });
    const res = await request(app)
      .post("/api/groups/g1/join")
      .set("Authorization", `Bearer ${user2Token}`)
      .send({});
    expect(res.status).toBe(403);
  });

  it("GET /api/groups/:id/members requires membership", async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] });
    const res = await request(app)
      .get("/api/groups/g1/members")
      .set("Authorization", `Bearer ${user2Token}`);
    expect(res.status).toBe(403);
  });

  it("GET /api/groups/:id/members returns masked phones for members", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ "?column?": 1 }] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({
        rows: [{ id: "u2", pseudo: "Jean", phone: "+243811111111", role: "member", joined_at: "2025-01-01" }],
      });
    const res = await request(app)
      .get("/api/groups/g1/members")
      .set("Authorization", `Bearer ${user2Token}`);
    expect(res.status).toBe(200);
    expect(res.body[0].phone).toContain("***");
  });

  it("POST /api/groups/:id/messages creates message for member", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ "?column?": 1 }] })
      .mockResolvedValueOnce({ rows: [{ name: "Voisins" }] })
      .mockResolvedValueOnce({ rows: [{ pseudo: "Jean" }] })
      .mockResolvedValueOnce({
        rows: [{
          id: "m1",
          group_id: "g1",
          user_id: "user-2",
          content: "Bonjour",
          created_at: "2025-01-01T00:00:00Z",
        }],
      })
      .mockResolvedValueOnce({ rows: [] });
    const res = await request(app)
      .post("/api/groups/g1/messages")
      .set("Authorization", `Bearer ${user2Token}`)
      .send({ content: "Bonjour" });
    expect(res.status).toBe(201);
    expect(res.body.content).toBe("Bonjour");
  });

  it("POST /api/groups/:id/alerts creates alert for member", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ "?column?": 1 }] })
      .mockResolvedValueOnce({ rows: [{ name: "Voisins" }] })
      .mockResolvedValueOnce({ rows: [{ pseudo: "Jean" }] })
      .mockResolvedValueOnce({
        rows: [{
          id: "a1",
          group_id: "g1",
          author_id: "user-2",
          type: "help_needed",
          title: "Coupure courant",
          body: null,
          lat: null,
          lng: null,
          created_at: "2025-01-01T00:00:00Z",
        }],
      })
      .mockResolvedValueOnce({ rows: [] });
    const res = await request(app)
      .post("/api/groups/g1/alerts")
      .set("Authorization", `Bearer ${user2Token}`)
      .send({ type: "help_needed", title: "Coupure courant" });
    expect(res.status).toBe(201);
    expect(res.body.type).toBe("help_needed");
  });
});

describe("History", () => {
  it("GET /api/history requires auth", async () => {
    const res = await request(app).get("/api/history");
    expect(res.status).toBe(401);
  });

  it("GET /api/history returns user incidents", async () => {
    mockQuery.mockResolvedValue({
      rows: [{ id: "i1", incident_type: "sos", status: "active", created_at: "2025-01-01T00:00:00Z" }],
    });
    const res = await request(app)
      .get("/api/history")
      .set("Authorization", `Bearer ${validToken}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body[0].incident_type).toBe("sos");
  });
});

describe("Structured group alerts", () => {
  it("POST /api/groups/:id/alerts accepts power_outage", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ "?column?": 1 }] })
      .mockResolvedValueOnce({ rows: [{ name: "Voisins" }] })
      .mockResolvedValueOnce({ rows: [{ pseudo: "Jean" }] })
      .mockResolvedValueOnce({
        rows: [{
          id: "a2",
          group_id: "g1",
          author_id: "user-2",
          type: "power_outage",
          title: "Plus de courant",
          body: null,
          lat: null,
          lng: null,
          created_at: "2025-01-01T00:00:00Z",
        }],
      })
      .mockResolvedValueOnce({ rows: [] });
    const res = await request(app)
      .post("/api/groups/g1/alerts")
      .set("Authorization", `Bearer ${user2Token}`)
      .send({ type: "power_outage", title: "Plus de courant" });
    expect(res.status).toBe(201);
    expect(res.body.type).toBe("power_outage");
  });
});

describe("Circle invites", () => {
  it("POST /api/invites/circle creates invite", async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [{
        id: "inv1",
        code: "ABCD1234",
        expires_at: "2025-01-03T00:00:00Z",
        max_uses: 5,
        use_count: 0,
        created_at: "2025-01-01T00:00:00Z",
      }],
    });
    const res = await request(app)
      .post("/api/invites/circle")
      .set("Authorization", `Bearer ${validToken}`)
      .send({ ttl_hours: 48 });
    expect(res.status).toBe(201);
    expect(res.body.invite.code).toBe("ABCD1234");
    expect(res.body.share_url).toMatch(/\/invite\//);
  });
});

describe("Public trip follow", () => {
  it("GET /api/public/trips/:token returns read-only trip", async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [{
        id: "t1",
        status: "active",
        dest_label: "Maison",
        eta_at: "2025-01-01T01:00:00Z",
        origin_lat: -4.3,
        origin_lng: 15.3,
        dest_lat: -4.31,
        dest_lng: 15.31,
        last_lat: -4.305,
        last_lng: 15.305,
        last_ping_at: "2025-01-01T00:30:00Z",
        abnormal_stop_at: null,
        share_expires_at: "2025-01-02T00:00:00Z",
        created_at: "2025-01-01T00:00:00Z",
        arrived_at: null,
        traveler_pseudo: "Marie",
      }],
    });
    const res = await request(app).get("/api/public/trips/abc123token99");
    expect(res.status).toBe(200);
    expect(res.body.read_only).toBe(true);
    expect(res.body.trip.traveler_pseudo).toBe("Marie");
  });
});

describe("App version", () => {
  const prev = {};
  beforeEach(() => {
    for (const k of ["APP_LATEST_VERSION", "APP_MIN_VERSION", "APP_FORCE_UPDATE", "APP_STORE_URL"]) {
      prev[k] = process.env[k];
    }
  });
  afterEach(() => {
    for (const k of Object.keys(prev)) {
      if (prev[k] === undefined) delete process.env[k];
      else process.env[k] = prev[k];
    }
  });

  it("GET /api/app/version returns policy from env", async () => {
    process.env.APP_LATEST_VERSION = "1.0.2";
    process.env.APP_MIN_VERSION = "1.0.0";
    process.env.APP_FORCE_UPDATE = "false";
    process.env.APP_STORE_URL = "https://play.google.com/store/apps/details?id=com.safealert.safealert";
    const res = await request(app).get("/api/app/version");
    expect(res.status).toBe(200);
    expect(res.body.latestVersion).toBe("1.0.2");
    expect(res.body.minVersion).toBe("1.0.0");
    expect(res.body.forceUpdate).toBe(false);
    expect(res.body.storeUrl).toContain("com.safealert.safealert");
  });

  it("GET /api/app/version forceUpdate when APP_FORCE_UPDATE=true", async () => {
    process.env.APP_FORCE_UPDATE = "true";
    process.env.APP_LATEST_VERSION = "1.0.2";
    const res = await request(app).get("/api/app/version");
    expect(res.status).toBe(200);
    expect(res.body.forceUpdate).toBe(true);
  });

  it("GET /api/app/config returns flags and maintenance banner fields", async () => {
    process.env.FEATURE_MAINTENANCE_MODE = "false";
    process.env.FEATURE_SOS_ENABLED = "true";
    process.env.APP_LATEST_VERSION = "1.0.2";
    const res = await request(app).get("/api/app/config");
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty("sosEnabled", true);
    expect(res.body).toHaveProperty("maintenance", false);
    expect(res.body).toHaveProperty("features");
    expect(res.body.features).toHaveProperty("liveStatus");
    expect(res.body.latestVersion).toBe("1.0.2");
  });
});

describe("Admin audit logs", () => {
  it("GET /api/admin/audit-logs returns paginated rows", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ total: 1 }] })
      .mockResolvedValueOnce({
        rows: [
          {
            id: "a1",
            actor_id: "admin-1",
            action: "user.role_update",
            entity_type: "user",
            entity_id: "user-1",
            metadata: {},
            ip: "127.0.0.1",
            created_at: new Date().toISOString(),
            actor_pseudo: "Admin",
            actor_phone: "+243811111111",
          },
        ],
      });
    const res = await request(app)
      .get("/api/admin/audit-logs?page=1&limit=10")
      .set("Authorization", `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].action).toBe("user.role_update");
    expect(res.body.total).toBe(1);
  });
});

describe("Sessions revoke", () => {
  it("POST /api/auth/sessions/revoke-all revokes other devices", async () => {
    const sessionToken = jwt.sign(
      { userId: "user-1", role: "citizen", jti: "jti-current", deviceId: "dev-1" },
      process.env.JWT_SECRET
    );
    mockQuery
      .mockResolvedValueOnce({ rows: [{ id: "dev-row" }] }) // session check in authenticate
      .mockResolvedValueOnce({ rows: [] }) // revoke update
      .mockResolvedValueOnce({ rows: [] }); // audit (optional)
    const res = await request(app)
      .post("/api/auth/sessions/revoke-all")
      .set("Authorization", `Bearer ${sessionToken}`)
      .send({ keep_current: true });
    expect(res.status).toBe(200);
    expect(res.body.message).toMatch(/déconnectés/i);
  });
});

describe("Heatmap slots", () => {
  it("GET /api/map/heatmap accepts slot=evening", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ zone_name: "Gombe", total: 2, alerts: 1, vigilance: 1, danger: 0, avg_lat: -4.3, avg_lng: 15.3 }] })
      .mockResolvedValueOnce({ rows: [{ total: 0, alerts: 0 }] });
    const res = await request(app).get("/api/map/heatmap?days=7&slot=evening");
    expect(res.status).toBe(200);
    expect(res.body.slot).toBe("evening");
    expect(res.body.available_slots).toContain("weekend");
  });
});
