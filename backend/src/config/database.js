const { Pool } = require("pg");

// Neon (surtout depuis Render EU) peut dépasser 5s au cold start
const connectionTimeoutMillis = Number(process.env.DB_CONNECTION_TIMEOUT_MS || 30000);

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: Number(process.env.DB_POOL_MAX || 20),
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis,
  ssl:
    process.env.DATABASE_URL && process.env.DATABASE_URL.includes("sslmode=require")
      ? { rejectUnauthorized: false }
      : undefined,
});

pool.on("error", (err) => {
  console.error("Unexpected error on idle client", err);
});

module.exports = { pool };
