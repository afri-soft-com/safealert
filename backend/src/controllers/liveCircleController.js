const crypto = require("crypto");
const { pool } = require("../config/database");
const { liveCircles } = require("../config/features");
const { getEntitlementsForUser } = require("../services/premiumEntitlements");

const assertEnabled = (res) => {
  if (!liveCircles()) {
    res.status(503).json({ error: "Cercles live désactivés" });
    return false;
  }
  return true;
};

const listMine = async (req, res) => {
  if (!assertEnabled(res)) return;
  try {
    const r = await pool.query(
      `SELECT c.*, m.role AS my_role, m.share_until
       FROM live_circles c
       JOIN live_circle_members m ON m.circle_id = c.id
       WHERE m.user_id = $1
       ORDER BY c.created_at DESC`,
      [req.userId]
    );
    return res.json(r.rows);
  } catch (err) {
    console.error("liveCircle listMine error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const createCircle = async (req, res) => {
  if (!assertEnabled(res)) return;
  const name = String(req.body.name || "Famille").trim().slice(0, 80);
  try {
    const ents = await getEntitlementsForUser(req.userId);
    const owned = await pool.query(
      `SELECT COUNT(*)::int AS c FROM live_circles WHERE owner_id = $1`,
      [req.userId]
    );
    const max = ents.live_circles_max ?? 1;
    if (owned.rows[0].c >= max) {
      return res.status(403).json({
        error: `Limite de ${max} cercle(s). Passez Premium pour en créer plus.`,
        code: "PREMIUM_REQUIRED",
      });
    }
    const code = crypto.randomBytes(3).toString("hex").toUpperCase();
    const circle = await pool.query(
      `INSERT INTO live_circles (owner_id, name, invite_code)
       VALUES ($1, $2, $3) RETURNING *`,
      [req.userId, name || "Famille", code]
    );
    await pool.query(
      `INSERT INTO live_circle_members (circle_id, user_id, role, share_until)
       VALUES ($1, $2, 'owner', NOW() + INTERVAL '24 hours')`,
      [circle.rows[0].id, req.userId]
    );
    return res.status(201).json(circle.rows[0]);
  } catch (err) {
    console.error("liveCircle create error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const joinCircle = async (req, res) => {
  if (!assertEnabled(res)) return;
  const code = String(req.body.code || "").trim().toUpperCase();
  if (code.length < 4) {
    return res.status(400).json({ error: "Code invalide" });
  }
  try {
    const circle = await pool.query(
      `SELECT * FROM live_circles WHERE invite_code = $1`,
      [code]
    );
    if (circle.rows.length === 0) {
      return res.status(404).json({ error: "Cercle introuvable" });
    }
    await pool.query(
      `INSERT INTO live_circle_members (circle_id, user_id, role, share_until)
       VALUES ($1, $2, 'member', NOW() + INTERVAL '24 hours')
       ON CONFLICT (circle_id, user_id) DO UPDATE SET share_until = EXCLUDED.share_until`,
      [circle.rows[0].id, req.userId]
    );
    return res.json(circle.rows[0]);
  } catch (err) {
    console.error("liveCircle join error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const setShare = async (req, res) => {
  if (!assertEnabled(res)) return;
  const hours = Math.min(Math.max(parseInt(req.body.hours, 10) || 24, 1), 72);
  try {
    const r = await pool.query(
      `UPDATE live_circle_members SET share_until = NOW() + ($3::int * INTERVAL '1 hour')
       WHERE circle_id = $1 AND user_id = $2
       RETURNING *`,
      [req.params.id, req.userId, hours]
    );
    if (r.rows.length === 0) {
      return res.status(404).json({ error: "Membre introuvable" });
    }
    return res.json(r.rows[0]);
  } catch (err) {
    console.error("liveCircle setShare error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const membersLive = async (req, res) => {
  if (!assertEnabled(res)) return;
  try {
    const member = await pool.query(
      `SELECT 1 FROM live_circle_members WHERE circle_id = $1 AND user_id = $2`,
      [req.params.id, req.userId]
    );
    if (member.rows.length === 0) {
      return res.status(403).json({ error: "Accès refusé" });
    }
    const r = await pool.query(
      `SELECT u.id, u.pseudo, u.last_lat, u.last_lng, u.last_seen_at,
              m.role, m.share_until, u.share_presence
       FROM live_circle_members m
       JOIN users u ON u.id = m.user_id
       WHERE m.circle_id = $1
         AND m.share_until > NOW()
         AND COALESCE(u.share_presence, true) = true
         AND u.last_lat IS NOT NULL AND u.last_lng IS NOT NULL`,
      [req.params.id]
    );
    return res.json(r.rows);
  } catch (err) {
    console.error("liveCircle membersLive error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = {
  listMine,
  createCircle,
  joinCircle,
  setShare,
  membersLive,
};
