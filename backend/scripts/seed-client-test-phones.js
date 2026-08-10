/**
 * Upsert non-admin client test phones on the DB pointed by DATABASE_URL / PROD_DATABASE_URL.
 * Usage: DATABASE_URL=... node scripts/seed-client-test-phones.js
 */
const { Pool } = require("pg");

const url = process.env.PROD_DATABASE_URL || process.env.DATABASE_URL;
if (!url) {
  console.error("Set DATABASE_URL or PROD_DATABASE_URL");
  process.exit(1);
}

const phones = [
  { phone: "+243810000001", pseudo: "TestCitoyen", role: "citizen" },
  { phone: "+243810000002", pseudo: "TestLeader", role: "leader" },
  { phone: "+243810000003", pseudo: "TestAgent", role: "agent" },
];

async function main() {
  const pool = new Pool({
    connectionString: url,
    ssl: url.includes("render.com") ? { rejectUnauthorized: false } : undefined,
  });
  try {
    for (const u of phones) {
      const r = await pool.query(
        `INSERT INTO users (phone, pseudo, role)
         VALUES ($1, $2, $3)
         ON CONFLICT (phone) DO UPDATE SET
           role = EXCLUDED.role,
           pseudo = COALESCE(users.pseudo, EXCLUDED.pseudo),
           updated_at = NOW()
         RETURNING id, phone, pseudo, role`,
        [u.phone, u.pseudo, u.role]
      );
      console.log(JSON.stringify(r.rows[0]));
    }
  } finally {
    await pool.end();
  }
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
