const request = require("supertest");
const path = require("path");
const jwt = require("jsonwebtoken");

const mockQuery = vi.fn();
const mockClientQuery = vi.fn();
const mockClient = { query: mockClientQuery, release: vi.fn() };
const dbPath = path.resolve(__dirname, "../src/config/database.js");
require.cache[dbPath] = {
  exports: {
    pool: { query: mockQuery, connect: vi.fn().mockResolvedValue(mockClient), on: vi.fn() },
  },
};

const mockSendPushToUser = vi.fn().mockResolvedValue(1);
const pushPath = path.resolve(__dirname, "../src/services/pushTargets.js");
require.cache[pushPath] = {
  id: pushPath,
  filename: pushPath,
  loaded: true,
  exports: { sendPushToUser: mockSendPushToUser, getUserPushTargets: vi.fn().mockResolvedValue([]) },
};

process.env.JWT_SECRET = "test-secret";
const { app } = require("../src/server");
const { evaluateRain, buildGrid } = require("../src/services/floodAlerts");
const { processSilentTrips } = require("../src/controllers/tripController");

const auth = (userId = "u1", role = "citizen") =>
  `Bearer ${jwt.sign({ userId, role }, process.env.JWT_SECRET)}`;

/** Answers pool queries by matching SQL fragments, first rule wins. */
function routeQueries(rules) {
  mockQuery.mockImplementation(async (sql) => {
    for (const [fragment, result] of rules) {
      if (String(sql).includes(fragment)) return result;
    }
    return { rows: [] };
  });
}

/** notifyTrustContacts reads the sender through a pooled client. */
function senderIs(pseudo) {
  mockClientQuery.mockImplementation(async (sql) => {
    if (String(sql).includes("SELECT pseudo, phone FROM users")) {
      return { rows: [{ pseudo, phone: "+243810000000" }] };
    }
    return { rows: [] };
  });
}

beforeEach(() => {
  mockQuery.mockReset();
  mockQuery.mockResolvedValue({ rows: [] });
  mockClientQuery.mockReset();
  mockClientQuery.mockResolvedValue({ rows: [] });
  mockSendPushToUser.mockClear();
});

describe("low battery", () => {
  it("rejects a level above 10 %", async () => {
    const res = await request(app)
      .post("/api/battery/low")
      .set("Authorization", auth())
      .send({ battery_pct: 40 });
    expect(res.status).toBe(400);
  });

  it("does nothing without an active trip or SOS", async () => {
    routeQueries([["AS trip", { rows: [{ trip: false, sos: false }] }]]);
    const res = await request(app)
      .post("/api/battery/low")
      .set("Authorization", auth())
      .send({ battery_pct: 4, lat: -4.3, lng: 15.3 });
    expect(res.body).toEqual({ notified: false, reason: "no_active_trip_or_sos" });
  });

  it("respects the cooldown", async () => {
    routeQueries([
      ["AS trip", { rows: [{ trip: true, sos: false }] }],
      ["low_battery_notified_at = NOW()", { rows: [] }],
    ]);
    const res = await request(app)
      .post("/api/battery/low")
      .set("Authorization", auth())
      .send({ battery_pct: 4 });
    expect(res.body.reason).toBe("cooldown");
  });

  it("notifies trust contacts during a trip", async () => {
    routeQueries([
      ["AS trip", { rows: [{ trip: true, sos: false }] }],
      ["low_battery_notified_at = NOW()", { rows: [{ last_lat: -4.3, last_lng: 15.3 }] }],
    ]);
    senderIs("Amani");
    const res = await request(app)
      .post("/api/battery/low")
      .set("Authorization", auth())
      .send({ battery_pct: 3, lat: -4.31, lng: 15.31 });
    expect(res.status).toBe(200);
    expect(res.body.notified).toBe(true);
  });
});

describe("medical card", () => {
  it("rejects an unknown blood type", async () => {
    const res = await request(app)
      .put("/api/medical-card")
      .set("Authorization", auth())
      .send({ blood_type: "Z+" });
    expect(res.status).toBe(400);
  });

  it("is hidden when there is no active SOS", async () => {
    routeQueries([
      ["FROM medical_cards m", { rows: [{ user_id: "u2", blood_type: "O+" }] }],
      ["FROM incidents", { rows: [] }],
    ]);
    const res = await request(app).get("/api/medical-card/u2").set("Authorization", auth("u1"));
    expect(res.status).toBe(403);
  });

  it("is hidden from someone who is not a trust contact", async () => {
    routeQueries([
      ["FROM medical_cards m", { rows: [{ user_id: "u2", blood_type: "O+" }] }],
      ["FROM incidents", { rows: [{ x: 1 }] }],
      ["FROM trust_contacts", { rows: [] }],
    ]);
    const res = await request(app).get("/api/medical-card/u2").set("Authorization", auth("u1"));
    expect(res.status).toBe(403);
  });

  it("is shown to a trust contact during an SOS", async () => {
    routeQueries([
      ["FROM medical_cards m", { rows: [{ user_id: "u2", blood_type: "O+" }] }],
      ["FROM incidents", { rows: [{ x: 1 }] }],
      ["FROM trust_contacts", { rows: [{ x: 1 }] }],
    ]);
    const res = await request(app).get("/api/medical-card/u2").set("Authorization", auth("u1"));
    expect(res.status).toBe(200);
    expect(res.body.card.blood_type).toBe("O+");
  });
});

describe("refuges", () => {
  it("lists nearest first without an account", async () => {
    routeQueries([["FROM refuge_places", { rows: [{ id: "r1", name: "Centre", distance_km: 0.4 }] }]]);
    const res = await request(app).get("/api/refuges?lat=-4.3&lng=15.3");
    expect(res.status).toBe(200);
    expect(res.body.refuges).toHaveLength(1);
    const sql = mockQuery.mock.calls.map((c) => String(c[0])).find((q) => q.includes("refuge_places"));
    expect(sql).toContain("ORDER BY r.distance_km ASC");
  });

  it("only lets leaders and admins add a place", async () => {
    const res = await request(app)
      .post("/api/refuges")
      .set("Authorization", auth("u1", "citizen"))
      .send({ name: "Pharmacie", category: "pharmacy", lat: -4.3, lng: 15.3 });
    expect(res.status).toBe(403);
  });

  it("lets a leader add a place", async () => {
    mockQuery.mockResolvedValue({ rows: [{ id: "r1", name: "Pharmacie", role: "leader" }] });
    const res = await request(app)
      .post("/api/refuges")
      .set("Authorization", auth("l1", "leader"))
      .send({ name: "Pharmacie", category: "pharmacy", lat: -4.3, lng: 15.3 });
    expect(res.status).toBe(201);
  });
});

describe("group voice notes", () => {
  it("rejects something that is not audio", async () => {
    const res = await request(app)
      .post("/api/groups/g1/messages")
      .set("Authorization", auth())
      .send({ audio_data_url: "data:text/html;base64,PHNjcmlwdD4=", audio_seconds: 3 });
    expect(res.status).toBe(400);
  });

  it("rejects a voice note without a valid length", async () => {
    const res = await request(app)
      .post("/api/groups/g1/messages")
      .set("Authorization", auth())
      .send({ audio_data_url: "data:audio/mp4;base64,AAAA", audio_seconds: 0 });
    expect(res.status).toBe(400);
  });
});

describe("flood alerts", () => {
  const cfg = { mmPerHour: 15, mm3h: 30, step: 0.1, south: -4.5, west: 15.1, north: -4.3, east: 15.3 };

  it("flags a heavy hour", () => {
    expect(evaluateRain([0, 2, 18, 1], cfg)).toMatchObject({ heavy: true, hoursAhead: 2, peakMm: 18 });
  });

  it("flags a heavy 3-hour total", () => {
    expect(evaluateRain([10, 11, 12, 0], cfg)).toMatchObject({ heavy: true, sum3hMm: 33 });
  });

  it("ignores light rain", () => {
    expect(evaluateRain([1, 3, 2, 0, 0, 4], cfg).heavy).toBe(false);
  });

  it("builds a grid inside the box", () => {
    const grid = buildGrid(cfg);
    expect(grid.length).toBe(4);
    for (const c of grid) {
      expect(c.lat).toBeGreaterThan(cfg.south);
      expect(c.lat).toBeLessThan(cfg.north);
    }
  });
});

describe("trip without news", () => {
  it("claims silent trips once and notifies contacts", async () => {
    routeQueries([
      ["signal_lost_notified_at = NOW()", { rows: [{ id: "t1", user_id: "u1", last_lat: -4.3, last_lng: 15.3 }] }],
    ]);
    senderIs("Amani");
    const n = await processSilentTrips();
    expect(n).toBe(1);
    const sql = mockQuery.mock.calls.map((c) => String(c[0])).find((q) => q.includes("signal_lost_notified_at"));
    expect(sql).toContain("signal_lost_notified_at IS NULL");
  });
});
