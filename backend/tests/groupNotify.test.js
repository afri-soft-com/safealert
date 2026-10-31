const path = require("path");

const mockQuery = vi.fn();
const mockSendPushToUser = vi.fn().mockResolvedValue(1);
const mockSendSMS = vi.fn().mockResolvedValue(true);

const dbPath = path.resolve(__dirname, "../src/config/database.js");
require.cache[dbPath] = {
  id: dbPath,
  filename: dbPath,
  loaded: true,
  exports: { pool: { query: mockQuery } },
};

const pushTargetsPath = path.resolve(__dirname, "../src/services/pushTargets.js");
require.cache[pushTargetsPath] = {
  id: pushTargetsPath,
  filename: pushTargetsPath,
  loaded: true,
  exports: { sendPushToUser: mockSendPushToUser },
};

const smsPath = path.resolve(__dirname, "../src/services/sms.js");
require.cache[smsPath] = {
  id: smsPath,
  filename: smsPath,
  loaded: true,
  exports: { sendSMS: mockSendSMS },
};

const servicePath = path.resolve(__dirname, "../src/services/groupNotify.js");
delete require.cache[servicePath];

const {
  notifyUserGroupsOnSOS,
  notifyUserGroupsOnReport,
  notifyUserGroupsOnFalseAlarm,
  notifyUserGroupsOnSafe,
} = require("../src/services/groupNotify");

describe("notifyUserGroupsOnSOS", () => {
  beforeEach(() => {
    mockQuery.mockReset();
    mockSendPushToUser.mockClear();
    mockSendSMS.mockClear();
  });

  it("skips when sos_notify_groups is false", async () => {
    mockQuery.mockResolvedValueOnce({ rows: [{ sos_notify_groups: false }] });
    const out = await notifyUserGroupsOnSOS("u1", -4.3, 15.3, "Alice");
    expect(out.groupsNotified).toBe(0);
    expect(out.alertsCreated).toBe(0);
    expect(mockQuery).toHaveBeenCalledTimes(1);
  });

  it("inserts alert, pushes and SMS other members", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ sos_notify_groups: true }] })
      .mockResolvedValueOnce({ rows: [{ id: "g1", name: "Voisins" }] })
      .mockResolvedValueOnce({ rows: [{ id: "a1" }] }) // INSERT alert
      .mockResolvedValueOnce({
        rows: [{ id: "u2", pseudo: "Bob", phone: "+243810000000" }],
      }) // otherMembers count
      .mockResolvedValueOnce({
        rows: [{ id: "u2", pseudo: "Bob" }],
      }) // member user ids for push
      .mockResolvedValueOnce({
        rows: [{ id: "u2", pseudo: "Bob", phone: "+243810000000" }],
      }); // contactable for SMS

    const out = await notifyUserGroupsOnSOS("u1", -4.321, 15.312, "Alice", "Gombe");

    expect(out.groupsNotified).toBe(1);
    expect(out.alertsCreated).toBe(1);
    expect(out.otherMembers).toBe(1);
    expect(out.pushNotified).toBe(1);
    expect(out.smsNotified).toBe(1);
    expect(mockSendPushToUser).toHaveBeenCalledTimes(1);
    expect(mockSendSMS).toHaveBeenCalledTimes(1);
  });

  it("still creates feed alert when no FCM tokens", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ sos_notify_groups: true }] })
      .mockResolvedValueOnce({ rows: [{ id: "g1", name: "Voisins" }] })
      .mockResolvedValueOnce({ rows: [{ id: "a1" }] })
      .mockResolvedValueOnce({ rows: [] }) // otherMembers
      .mockResolvedValueOnce({ rows: [] }) // no members for push
      .mockResolvedValueOnce({ rows: [] }); // no phones

    const out = await notifyUserGroupsOnSOS("u1", -4.3, 15.3, "Alice");
    expect(out.alertsCreated).toBe(1);
    expect(out.alone).toBe(true);
    expect(out.pushNotified).toBe(0);
    expect(mockSendPushToUser).not.toHaveBeenCalled();
  });
});

describe("notifyUserGroupsOnReport", () => {
  beforeEach(() => {
    mockQuery.mockReset();
    mockSendPushToUser.mockClear();
    mockSendSMS.mockClear();
  });

  it("publishes signalement without SMS", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ sos_notify_groups: true }] })
      .mockResolvedValueOnce({ rows: [{ id: "g1", name: "Voisins" }] })
      .mockResolvedValueOnce({ rows: [{ id: "a1" }] })
      .mockResolvedValueOnce({
        rows: [{ id: "u2", pseudo: "Bob", phone: "+243810000001" }],
      }) // otherMembers
      .mockResolvedValueOnce({
        rows: [{ id: "u2", pseudo: "Bob" }],
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
    expect(out.pushNotified).toBe(1);
    expect(mockSendSMS).not.toHaveBeenCalled();
    expect(mockSendPushToUser.mock.calls[0][1].data.type).toBe("group_report");
  });
});

describe("notifyUserGroupsOnFalseAlarm / OnSafe", () => {
  beforeEach(() => {
    mockQuery.mockReset();
    mockSendPushToUser.mockClear();
    mockSendSMS.mockClear();
  });

  it("notifies groups of false alarm with SMS and info feed", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ sos_notify_groups: true }] })
      .mockResolvedValueOnce({ rows: [{ id: "g1", name: "Voisins" }] })
      .mockResolvedValueOnce({ rows: [{ id: "a1" }] })
      .mockResolvedValueOnce({
        rows: [{ id: "u2", pseudo: "Bob", phone: "+243810000002" }],
      })
      .mockResolvedValueOnce({
        rows: [{ id: "u2", pseudo: "Bob" }],
      })
      .mockResolvedValueOnce({
        rows: [{ id: "u2", pseudo: "Bob", phone: "+243810000002" }],
      });

    const out = await notifyUserGroupsOnFalseAlarm(
      "u1",
      -4.3,
      15.3,
      "Alice",
      "Gombe"
    );

    expect(out.alertsCreated).toBe(1);
    expect(out.pushNotified).toBe(1);
    expect(out.smsNotified).toBe(1);
    expect(mockSendPushToUser.mock.calls[0][1].data.type).toBe("group_false_alarm");
    expect(mockQuery.mock.calls[2][0]).toMatch(/INSERT INTO group_alerts/);
    expect(mockQuery.mock.calls[2][1][2]).toBe("info");
  });

  it("notifies groups when member confirms safe", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ sos_notify_groups: true }] })
      .mockResolvedValueOnce({ rows: [{ id: "g1", name: "Voisins" }] })
      .mockResolvedValueOnce({ rows: [{ id: "a1" }] })
      .mockResolvedValueOnce({
        rows: [{ id: "u2", pseudo: "Bob", phone: "+243810000003" }],
      })
      .mockResolvedValueOnce({
        rows: [{ id: "u2", pseudo: "Bob" }],
      })
      .mockResolvedValueOnce({
        rows: [{ id: "u2", pseudo: "Bob", phone: "+243810000003" }],
      });

    const out = await notifyUserGroupsOnSafe("u1", -4.3, 15.3, "Alice");
    expect(out.alertsCreated).toBe(1);
    expect(mockSendPushToUser.mock.calls[0][1].data.type).toBe("group_safe");
    expect(mockSendSMS).toHaveBeenCalled();
  });
});
