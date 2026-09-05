/**
 * One-shot wipe: keep only the platform_admin superadmin.
 * Usage (from backend/):
 *   $env:CONFIRM="WIPE_KEEP_SUPERADMIN"
 *   npm run wipe:keep-superadmin
 */
require("dotenv").config({ path: require("path").join(__dirname, "../.env") });
if (process.env.DATABASE_URL_DIRECT) {
  process.env.DATABASE_URL = process.env.DATABASE_URL_DIRECT;
}

const { pool } = require("../src/config/database");
const {
  wipeKeepSuperadmin,
  DEFAULT_KEEP_PHONE,
} = require("../src/services/wipeKeepSuperadmin");

async function main() {
  if (process.env.CONFIRM !== "WIPE_KEEP_SUPERADMIN") {
    console.error("Refus : définir CONFIRM=WIPE_KEEP_SUPERADMIN");
    process.exit(1);
  }
  if (!process.env.DATABASE_URL) {
    console.error("DATABASE_URL manquant");
    process.exit(1);
  }

  const keepPhone = process.env.KEEP_PHONE || DEFAULT_KEEP_PHONE;
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await wipeKeepSuperadmin(client, { keepPhone });
    await client.query("COMMIT");
    console.log(
      JSON.stringify({
        ok: true,
        keptRole: result.keptRole,
        usersBefore: result.usersBefore,
        usersAfter: result.usersAfter,
        deletedUsers: result.deletedUsers,
      })
    );
  } catch (err) {
    try {
      await client.query("ROLLBACK");
    } catch (_) {
      /* ignore */
    }
    console.error(err.message || err);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

main();
