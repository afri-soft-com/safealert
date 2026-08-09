const { pool } = require("../config/database");
const { auditLog } = require("../config/features");

const writeAudit = async ({
  actorId,
  action,
  entityType,
  entityId = null,
  metadata = null,
  ip = null,
}) => {
  if (!auditLog()) return;
  try {
    await pool.query(
      `INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, metadata, ip)
       VALUES ($1, $2, $3, $4, $5::jsonb, $6)`,
      [
        actorId || null,
        action,
        entityType,
        entityId,
        metadata ? JSON.stringify(metadata) : null,
        ip,
      ]
    );
  } catch (err) {
    console.error("audit write error:", err.message);
  }
};

module.exports = { writeAudit };
