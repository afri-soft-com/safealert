const path = require("path");

const mockQuery = vi.fn();
const mockSendPush = vi.fn().mockResolvedValue(true);

const dbPath = path.resolve(__dirname, "../src/config/database.js");
require.cache[dbPath] = {
  id: dbPath,
  filename: dbPath,
  loaded: true,
  exports: { pool: { query: mockQuery } },
};

const firebasePath = path.resolve(__dirname, "../src/config/firebase.js");
require.cache[firebasePath] = {
  id: firebasePath,
  filename: firebasePath,
  loaded: true,
  exports: { sendPush: mockSendPush },
};

// Clear cached module so it picks up our mocks
const servicePath = path.resolve(__dirname, "../src/services/groupNotify.js");
delete require.cache[servicePath];

const {
  notifyUserGroupsOnSOS,
  notifyUserGroupsOnReport,
} = require("../src/services/groupNotify");

describe("notifyUserGroupsOnSOS", () => {
  beforeEach(() => {
    mockQuery.mockReset();
    mockSendPush.mockClear();
  });

  it("skips when sos_notify_groups is false", async () => {
    mockQuery.mockResolvedValueOnce({ rows: [{ sos_notify_groups: false }] });
    const out = await notifyUserGroupsOnSOS("u1", -4.3, 15.3, "Alice");
    expect(out).toEqual({ groupsNotified: 0, membersNotified: 0, alertsCreated: 0 });
    expect(mockQuery).toHaveBeenCalledTimes(1);
  });

  it("inserts a group_alerts row and notifies members", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ sos_notify_groups: true }] })
      .mockResolvedValueOnce({ rows: [{ id: "g1", name: "Voisins" }] })
      .mockResolvedValueOnce({ rows: [{ id: "a1" }] })
      .mockResolvedValueOnce({
        rows: [{ id: "u2", fcm_token: "tok", pseudo: "Bob" }],
      });

    const out = await notifyUserGroupsOnSOS("u1", -4.321, 15.312, "Alice", "Gombe");

    expect(out.groupsNotified).toBe(1);
    expect(out.alertsCreated).toBe(1);
    expect(out.membersNotified).toBe(1);

    const insertCall = mockQuery.mock.calls.find(
      ([sql]) => typeof sql === "string" && sql.includes("INSERT INTO group_alerts")
    );
    expect(insertCall).toBeTruthy();
    expect(insertCall[1][0]).toBe("g1");
    expect(insertCall[1][1]).toBe("u1");
    expect(insertCall[1][3]).toMatch(/^SOS/);
    expect(mockSendPush).toHaveBeenCalledTimes(1);
  });

  it("still creates feed alert when no FCM tokens", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ sos_notify_groups: true }] })
      .mockResolvedValueOnce({ rows: [{ id: "g1", name: "Voisins" }] })
      .mockResolvedValueOnce({ rows: [{ id: "a1" }] })
      .mockResolvedValueOnce({ rows: [] }); // no device tokens

    const out = await notifyUserGroupsOnSOS("u1", -4.3, 15.3, "Alice");
    expect(out.alertsCreated).toBe(1);
    expect(out.membersNotified).toBe(0);
    expect(mockSendPush).not.toHaveBeenCalled();
  });
});

describe("notifyUserGroupsOnReport", () => {
  beforeEach(() => {
    mockQuery.mockReset();
    mockSendPush.mockClear();
  });

  it("publishes signalement into group feed and pushes members", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ sos_notify_groups: true }] })
      .mockResolvedValueOnce({ rows: [{ id: "g1", name: "Voisins" }] })
      .mockResolvedValueOnce({ rows: [{ id: "a1" }] })
      .mockResolvedValueOnce({
        rows: [{ id: "u2", fcm_token: "tok", pseudo: "Bob" }],
      });

    const out = await notifyUserGroupsOnReport(
      "u1",
      -4.3,
      15.3,
      "Alice",
      "Gombe",
      "vol"
    );

    expect(out.alertsCreated).toBe(1);
    expect(out.membersNotified).toBe(1);
    const insertCall = mockQuery.mock.calls.find(
      ([sql]) => typeof sql === "string" && sql.includes("INSERT INTO group_alerts")
    );
    expect(insertCall[1][3]).toMatch(/Signalement/);
    expect(mockSendPush.mock.calls[0][1].data.type).toBe("group_report");
  });
});
