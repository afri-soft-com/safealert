const {
  wipeKeepSuperadmin,
  DEFAULT_KEEP_PHONE,
} = require("../src/services/wipeKeepSuperadmin");

function makeClient(handlers) {
  return {
    query: vi.fn(async (sql, params) => {
      const normalized = sql.replace(/\s+/g, " ").trim();
      for (const h of handlers) {
        if (h.match(normalized, params)) return h.result(normalized, params);
      }
      return { rows: [], rowCount: 0 };
    }),
  };
}

describe("wipeKeepSuperadmin", () => {
  it("aborts if the keep user is missing", async () => {
    const client = makeClient([
      {
        match: (sql) => sql.includes("SELECT id, phone, role FROM users"),
        result: () => ({ rows: [], rowCount: 0 }),
      },
    ]);
    await expect(wipeKeepSuperadmin(client, { keepPhone: DEFAULT_KEEP_PHONE })).rejects.toThrow(
      /introuvable/
    );
  });

  it("aborts if the keep user is not platform_admin", async () => {
    const client = makeClient([
      {
        match: (sql) => sql.includes("SELECT id, phone, role FROM users"),
        result: () => ({
          rows: [{ id: "u1", phone: DEFAULT_KEEP_PHONE, role: "citizen" }],
          rowCount: 1,
        }),
      },
    ]);
    await expect(wipeKeepSuperadmin(client, { keepPhone: DEFAULT_KEEP_PHONE })).rejects.toThrow(
      /platform_admin/
    );
  });

  it("deletes other users and verifies a single remaining admin", async () => {
    const existing = new Set(["otp_codes", "incidents", "partner_api_keys"]);
    const client = makeClient([
      {
        match: (sql) => sql.includes("SELECT id, phone, role FROM users"),
        result: () => ({
          rows: [{ id: "keep-1", phone: DEFAULT_KEEP_PHONE, role: "platform_admin" }],
          rowCount: 1,
        }),
      },
      {
        match: (sql) => sql.startsWith("SELECT COUNT(*)"),
        result: () => ({ rows: [{ c: 1 }], rowCount: 1 }),
      },
      {
        match: (sql) => sql.includes("information_schema.tables"),
        result: (_sql, params) => ({
          rows: existing.has(params[0]) ? [{ "?column?": 1 }] : [],
          rowCount: existing.has(params[0]) ? 1 : 0,
        }),
      },
      {
        match: (sql) => sql.startsWith("DELETE FROM"),
        result: (sql) => ({
          rows: sql.includes("RETURNING") ? [] : [],
          rowCount: sql.includes("users") ? 4 : 2,
        }),
      },
      {
        match: (sql) => sql.includes("SELECT phone, role FROM users"),
        result: () => ({
          rows: [{ phone: DEFAULT_KEEP_PHONE, role: "platform_admin" }],
          rowCount: 1,
        }),
      },
    ]);

    const result = await wipeKeepSuperadmin(client, { keepPhone: DEFAULT_KEEP_PHONE });
    expect(result.usersAfter).toBe(1);
    expect(result.keptPhone).toBe(DEFAULT_KEEP_PHONE);
    expect(result.keptRole).toBe("platform_admin");
    expect(result.deletedFrom.otp_codes).toBe(2);
    expect(result.deletedFrom.users).toBe(4);
  });
});
