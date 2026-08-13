const crypto = require("crypto");
const { pool } = require("../config/database");
const { circleInvite } = require("../config/features");
const { sendPush } = require("../config/firebase");

const PUBLIC_BASE =
  process.env.PUBLIC_APP_URL ||
  process.env.API_PUBLIC_URL ||
  "https://safealert-api.onrender.com";

const createCircleInvite = async (req, res) => {
  if (!circleInvite()) {
    return res.status(503).json({ error: "Invitations désactivées" });
  }
  try {
    const code = crypto.randomBytes(4).toString("hex").toUpperCase();
    const hours = Math.min(Math.max(parseInt(req.body?.ttl_hours) || 48, 1), 168);
    const maxUses = Math.min(Math.max(parseInt(req.body?.max_uses) || 5, 1), 20);

    const result = await pool.query(
      `INSERT INTO circle_invites (inviter_id, code, expires_at, max_uses)
       VALUES ($1, $2, NOW() + ($3 * INTERVAL '1 hour'), $4)
       RETURNING id, code, expires_at, max_uses, use_count, created_at`,
      [req.userId, code, hours, maxUses]
    );
    const invite = result.rows[0];
    const deepLink = `safealert://invite/${invite.code}`;
    const webLink = `${PUBLIC_BASE.replace(/\/$/, "")}/invite/${invite.code}`;

    return res.status(201).json({
      invite,
      deep_link: deepLink,
      share_url: webLink,
      share_text: `Rejoins mon cercle SafeAlert avec le code ${invite.code} : ${webLink}`,
    });
  } catch (err) {
    console.error("createCircleInvite error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const acceptCircleInvite = async (req, res) => {
  if (!circleInvite()) {
    return res.status(503).json({ error: "Invitations désactivées" });
  }
  const code = String(req.body?.code || req.params?.code || "")
    .trim()
    .toUpperCase();
  if (!code || code.length < 4) {
    return res.status(400).json({ error: "Code d'invitation requis" });
  }

  try {
    const inv = await pool.query(
      `SELECT * FROM circle_invites
       WHERE code = $1 AND expires_at > NOW() AND use_count < max_uses`,
      [code]
    );
    if (inv.rows.length === 0) {
      return res.status(404).json({ error: "Invitation invalide ou expirée" });
    }
    const invite = inv.rows[0];
    if (String(invite.inviter_id) === String(req.userId)) {
      return res.status(400).json({ error: "Vous ne pouvez pas accepter votre propre invitation" });
    }

    const me = await pool.query(
      `SELECT id, phone, pseudo FROM users WHERE id = $1`,
      [req.userId]
    );
    const inviter = await pool.query(
      `SELECT id, phone, pseudo, fcm_token FROM users WHERE id = $1`,
      [invite.inviter_id]
    );
    if (me.rows.length === 0 || inviter.rows.length === 0) {
      return res.status(404).json({ error: "Utilisateur introuvable" });
    }

    const accepter = me.rows[0];
    const host = inviter.rows[0];

    // Add accepter into inviter's circle
    await pool.query(
      `INSERT INTO trust_contacts (user_id, contact_user_id, contact_name, contact_phone)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id, contact_phone) DO UPDATE
         SET contact_user_id = EXCLUDED.contact_user_id,
             contact_name = EXCLUDED.contact_name`,
      [host.id, accepter.id, accepter.pseudo, accepter.phone]
    );
    // Reciprocal: inviter into accepter's circle
    await pool.query(
      `INSERT INTO trust_contacts (user_id, contact_user_id, contact_name, contact_phone)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id, contact_phone) DO UPDATE
         SET contact_user_id = EXCLUDED.contact_user_id,
             contact_name = EXCLUDED.contact_name`,
      [accepter.id, host.id, host.pseudo, host.phone]
    );

    await pool.query(
      `UPDATE circle_invites SET use_count = use_count + 1 WHERE id = $1`,
      [invite.id]
    );

    if (host.fcm_token) {
      await sendPush(host.fcm_token, {
        notification: {
          title: "Cercle SafeAlert",
          body: `${accepter.pseudo} a rejoint votre cercle de confiance`,
        },
        data: { type: "circle_invite_accepted", userId: String(accepter.id) },
      });
    }

    return res.json({
      message: `${host.pseudo} a été ajouté à votre cercle`,
      contact: { name: host.pseudo, phone: host.phone },
    });
  } catch (err) {
    console.error("acceptCircleInvite error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

/** Public peek (no auth) — for deep-link landing */
const peekInvite = async (req, res) => {
  const code = String(req.params.code || "").trim().toUpperCase();
  try {
    const result = await pool.query(
      `SELECT ci.code, ci.expires_at, u.pseudo AS inviter_pseudo
       FROM circle_invites ci
       JOIN users u ON u.id = ci.inviter_id
       WHERE ci.code = $1 AND ci.expires_at > NOW() AND ci.use_count < ci.max_uses`,
      [code]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Invitation invalide ou expirée" });
    }
    return res.json(result.rows[0]);
  } catch (err) {
    console.error("peekInvite error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

module.exports = { createCircleInvite, acceptCircleInvite, peekInvite };
