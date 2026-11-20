const { pool } = require("../config/database");
// Leaders and agents respond to SOS too, so they may read the card.
const { STAFF_ROLES } = require("../services/realtime");

const BLOOD_TYPES = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"];
const TEXT_FIELDS = ["allergies", "conditions", "medications", "emergency_note"];
const MAX_TEXT = 500;

const EMPTY = {
  blood_type: null,
  allergies: null,
  conditions: null,
  medications: null,
  emergency_note: null,
  share_on_sos: true,
  updated_at: null,
};

const cleanText = (v) => {
  if (v == null) return null;
  const t = String(v).trim().slice(0, MAX_TEXT);
  return t.length ? t : null;
};

const getMine = async (req, res) => {
  try {
    const r = await pool.query(`SELECT * FROM medical_cards WHERE user_id = $1`, [req.userId]);
    return res.json({ card: r.rows[0] || { ...EMPTY, user_id: req.userId } });
  } catch (err) {
    console.error("medical getMine:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const saveMine = async (req, res) => {
  const body = req.body || {};
  let blood = body.blood_type == null || body.blood_type === "" ? null : String(body.blood_type).toUpperCase().trim();
  if (blood && !BLOOD_TYPES.includes(blood)) {
    return res.status(400).json({ error: `Groupe sanguin invalide (${BLOOD_TYPES.join(", ")}).` });
  }
  const values = TEXT_FIELDS.map((f) => cleanText(body[f]));
  const share = body.share_on_sos !== false;
  try {
    const r = await pool.query(
      `INSERT INTO medical_cards
         (user_id, blood_type, allergies, conditions, medications, emergency_note, share_on_sos, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
       ON CONFLICT (user_id) DO UPDATE SET
         blood_type = EXCLUDED.blood_type,
         allergies = EXCLUDED.allergies,
         conditions = EXCLUDED.conditions,
         medications = EXCLUDED.medications,
         emergency_note = EXCLUDED.emergency_note,
         share_on_sos = EXCLUDED.share_on_sos,
         updated_at = NOW()
       RETURNING *`,
      [req.userId, blood, ...values, share]
    );
    return res.json({ card: r.rows[0] });
  } catch (err) {
    console.error("medical saveMine:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

/**
 * GET /api/medical-card/:userId — a trust contact (or staff) reads the card
 * of someone who has an SOS running and chose to share it.
 */
const getForSos = async (req, res) => {
  const targetId = String(req.params.userId || "");
  if (!targetId) return res.status(400).json({ error: "Utilisateur requis" });
  if (targetId === String(req.userId)) return getMine(req, res);

  try {
    const r = await pool.query(
      `SELECT m.*, u.pseudo FROM medical_cards m
       JOIN users u ON u.id = m.user_id
       WHERE m.user_id = $1 AND m.share_on_sos = true`,
      [targetId]
    );
    if (r.rows.length === 0) {
      return res.status(404).json({ error: "Aucune fiche médicale partagée." });
    }

    const activeSos = await pool.query(
      `SELECT 1 FROM incidents
       WHERE user_id = $1 AND status IN ('active','verified','acknowledged','in_progress')
         AND incident_type IN ('sos','sos_discret')
         AND created_at > NOW() - INTERVAL '24 hours'
       LIMIT 1`,
      [targetId]
    );
    if (activeSos.rows.length === 0) {
      return res.status(403).json({ error: "La fiche n'est visible que pendant un SOS." });
    }

    if (!STAFF_ROLES.has(req.userRole)) {
      const contact = await pool.query(
        `SELECT 1 FROM trust_contacts WHERE user_id = $1 AND contact_user_id = $2 LIMIT 1`,
        [targetId, req.userId]
      );
      if (contact.rows.length === 0) {
        return res.status(403).json({ error: "Réservé aux contacts de confiance." });
      }
    }
    return res.json({ card: r.rows[0] });
  } catch (err) {
    console.error("medical getForSos:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = { getMine, saveMine, getForSos, BLOOD_TYPES };
