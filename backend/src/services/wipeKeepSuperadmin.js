const { normalizePhone } = require("../utils/phone");

const DEFAULT_KEEP_PHONE = "+243971163574";

/** Reference / catalog tables — never emptied by the wipe. */
const PRESERVE_TABLES = new Set([
  "users",
  "emergency_numbers",
  "landmarks",
  "route_corridors",
  "app_settings",
  "spatial_ref_sys",
  "geography_columns",
  "geometry_columns",
]);

/** Child / operational tables, FK-safe order (children first). */
const WIPE_TABLES = [
  "partner_webhook_deliveries",
  "incident_chat_messages",
  "incident_evidence",
  "incident_verifications",
  "sos_live_status",
  "check_ins",
  "group_messages",
  "group_alerts",
  "group_join_requests",
  "group_members",
  "safety_pings",
  "circle_invites",
  "contact_backups",
  "neighborhood_subscriptions",
  "trust_zones",
  "trust_contacts",
  "user_devices",
  "leader_sectors",
  "safe_trips",
  "otp_codes",
  "audit_logs",
  "neighborhood_groups",
  "incidents",
  "partner_api_keys",
];

async function tableExists(client, name) {
  const r = await client.query(
    `SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name = $1`,
    [name]
  );
  return r.rowCount > 0;
}

/**
 * Delete all production rows except the keep-phone user and catalog tables.
 * Idempotent. Does not drop schema or extensions.
 */
async function wipeKeepSuperadmin(client, { keepPhone = DEFAULT_KEEP_PHONE } = {}) {
  const normalized = normalizePhone(keepPhone) || String(keepPhone || "").trim();
  if (!normalized) {
    throw new Error("Numéro superadmin invalide");
  }

  const keep = await client.query(
    `SELECT id, phone, role FROM users WHERE phone = $1`,
    [normalized]
  );
  if (keep.rows.length === 0) {
    throw new Error("Superadmin introuvable — abandon (aucune suppression)");
  }
  const keepUser = keep.rows[0];
  if (keepUser.role !== "platform_admin") {
    throw new Error("Le compte à conserver n'est pas platform_admin — abandon");
  }

  const before = await client.query(`SELECT COUNT(*)::int AS c FROM users`);
  const deletedFrom = {};

  for (const table of WIPE_TABLES) {
    if (PRESERVE_TABLES.has(table)) continue;
    if (!(await tableExists(client, table))) continue;
    const res = await client.query(`DELETE FROM ${table}`);
    deletedFrom[table] = res.rowCount;
  }

  const deletedUsers = await client.query(
    `DELETE FROM users WHERE id <> $1 RETURNING id`,
    [keepUser.id]
  );
  deletedFrom.users = deletedUsers.rowCount;

  const after = await client.query(
    `SELECT COUNT(*)::int AS c FROM users`
  );
  const remaining = await client.query(
    `SELECT phone, role FROM users ORDER BY created_at`
  );

  if (after.rows[0].c !== 1 || remaining.rows[0].phone !== normalized) {
    throw new Error("Vérification échouée : le superadmin n'est pas le seul utilisateur");
  }

  return {
    keptPhone: keepUser.phone,
    keptRole: keepUser.role,
    usersBefore: before.rows[0].c,
    usersAfter: after.rows[0].c,
    deletedUsers: deletedUsers.rowCount,
    deletedFrom,
  };
}

module.exports = {
  wipeKeepSuperadmin,
  WIPE_TABLES,
  PRESERVE_TABLES,
  DEFAULT_KEEP_PHONE,
};
