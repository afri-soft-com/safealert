const { pool } = require("../config/database");
const { contactBackup } = require("../config/features");

/**
 * Client encrypts contacts (AES-GCM) with a key derived from user passphrase.
 * Server stores opaque ciphertext only — never plaintext contacts.
 */
const upsertBackup = async (req, res) => {
  if (!contactBackup()) {
    return res.status(503).json({ error: "Sauvegarde contacts désactivée" });
  }
  const { ciphertext, nonce, salt, contact_count, version } = req.body;
  if (!ciphertext || !nonce || !salt) {
    return res.status(400).json({ error: "ciphertext, nonce et salt requis" });
  }
  if (String(ciphertext).length > 500000) {
    return res.status(400).json({ error: "Sauvegarde trop volumineuse" });
  }
  try {
    const result = await pool.query(
      `INSERT INTO contact_backups (user_id, ciphertext, nonce, salt, version, contact_count, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, NOW())
       ON CONFLICT (user_id) DO UPDATE SET
         ciphertext = EXCLUDED.ciphertext,
         nonce = EXCLUDED.nonce,
         salt = EXCLUDED.salt,
         version = EXCLUDED.version,
         contact_count = EXCLUDED.contact_count,
         updated_at = NOW()
       RETURNING id, contact_count, version, updated_at`,
      [
        req.userId, ciphertext, nonce, salt,
        parseInt(version) || 1,
        parseInt(contact_count) || 0,
      ]
    );
    return res.json({ backup: result.rows[0] });
  } catch (err) {
    console.error("upsertBackup error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const getBackup = async (req, res) => {
  if (!contactBackup()) {
    return res.status(503).json({ error: "Sauvegarde contacts désactivée" });
  }
  try {
    const result = await pool.query(
      `SELECT ciphertext, nonce, salt, version, contact_count, updated_at
       FROM contact_backups WHERE user_id = $1`,
      [req.userId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Aucune sauvegarde" });
    }
    return res.json(result.rows[0]);
  } catch (err) {
    console.error("getBackup error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const deleteBackup = async (req, res) => {
  if (!contactBackup()) {
    return res.status(503).json({ error: "Sauvegarde contacts désactivée" });
  }
  try {
    await pool.query(`DELETE FROM contact_backups WHERE user_id = $1`, [req.userId]);
    return res.json({ message: "Sauvegarde supprimée" });
  } catch (err) {
    console.error("deleteBackup error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = { upsertBackup, getBackup, deleteBackup };
