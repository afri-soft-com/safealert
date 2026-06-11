const { pool } = require("../config/database");

const getContacts = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT tc.id, tc.contact_name, tc.contact_phone, tc.created_at,
              u.id as ref_user_id, u.pseudo, u.last_seen_at,
              CASE WHEN u.last_seen_at > NOW() - INTERVAL '5 minutes' THEN 'online' ELSE 'offline' END as status
       FROM trust_contacts tc
       LEFT JOIN users u ON tc.contact_phone = u.phone
       WHERE tc.user_id = $1
       ORDER BY tc.created_at DESC`,
      [req.userId]
    );
    return res.json(result.rows);
  } catch (err) {
    console.error("getContacts error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const addContact = async (req, res) => {
  const { contact_name, contact_phone } = req.body;
  if (!contact_name || !contact_phone) {
    return res.status(400).json({ error: "Nom et téléphone requis" });
  }
  try {
    const countRes = await pool.query(
      "SELECT COUNT(*)::int as count FROM trust_contacts WHERE user_id = $1",
      [req.userId]
    );
    if (countRes.rows[0].count >= 10) {
      return res.status(400).json({ error: "Maximum 10 contacts de confiance autorisés" });
    }

    const existing = await pool.query(
      "SELECT id FROM trust_contacts WHERE user_id = $1 AND contact_phone = $2",
      [req.userId, contact_phone]
    );
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: "Ce contact existe déjà" });
    }

    const result = await pool.query(
      `INSERT INTO trust_contacts (user_id, contact_name, contact_phone)
       VALUES ($1, $2, $3) RETURNING *`,
      [req.userId, contact_name, contact_phone]
    );
    return res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error("addContact error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const deleteContact = async (req, res) => {
  const { id } = req.params;
  try {
    const result = await pool.query(
      "DELETE FROM trust_contacts WHERE id = $1 AND user_id = $2 RETURNING id",
      [id, req.userId]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: "Contact non trouvé" });
    return res.json({ message: "Contact supprimé" });
  } catch (err) {
    console.error("deleteContact error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

module.exports = { getContacts, addContact, deleteContact };
