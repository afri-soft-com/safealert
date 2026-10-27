const path = require("path");

const mockQuery = vi.fn();
const mockSendPush = vi.fn().mockResolvedValue("msg-1");
const mockSendSMS = vi.fn().mockResolvedValue(true);

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
} = require("../src/services/groupNotify");

describe("notifyUserGroupsOnSOS", () => {
  beforeEach(() => {
    mockQuery.mockReset();
    mockSendPush.mockClear();
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
        rows: [{ id: "u2", fcm_token: "tok", pseudo: "Bob" }],
      }) // tokens
      .mockResolvedValueOnce({
        rows: [{ id: "u2", pseudo: "Bob", phone: "+243810000000" }],
      }); // contactable for SMS

    const out = await notifyUserGroupsOnSOS("u1", -4.321, 15.312, "Alice", "Gombe");

    expect(out.groupsNotified).toBe(1);
    expect(out.alertsCreated).toBe(1);
    expect(out.pushNotified).toBe(1);
    expect(out.smsNotified).toBe(1);
    expect(mockSendPush).toHaveBeenCalledTimes(1);
    expect(mockSendSMS).toHaveBeenCalledTimes(1);
  });

  it("still creates feed alert when no FCM tokens", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ sos_notify_groups: true }] })
      .mockResolvedValueOnce({ rows: [{ id: "g1", name: "Voisins" }] })
      .mockResolvedValueOnce({ rows: [{ id: "a1" }] })
      .mockResolvedValueOnce({ rows: [] }) // no tokens
      .mockResolvedValueOnce({ rows: [] }); // no phones

    const out = await notifyUserGroupsOnSOS("u1", -4.3, 15.3, "Alice");
    expect(out.alertsCreated).toBe(1);
    expect(out.pushNotified).toBe(0);
    expect(mockSendPush).not.toHaveBeenCalled();
  });
});

describe("notifyUserGroupsOnReport", () => {
  beforeEach(() => {
    mockQuery.mockReset();
    mockSendPush.mockClear();
    mockSendSMS.mockClear();
  });

  it("publishes signalement without SMS", async () => {
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
    expect(out.pushNotified).toBe(1);
    expect(mockSendSMS).not.toHaveBeenCalled();
    expect(mockSendPush.mock.calls[0][1].data.type).toBe("group_report");
  });
});
