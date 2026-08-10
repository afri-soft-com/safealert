const { pool } = require("../config/database");
const { premium } = require("../config/features");

/**
 * Premium stub — no payment processor required.
 * Admins can grant via POST /api/premium/grant; users can see status.
 * When FEATURE_PREMIUM=false, all users are treated as free-tier.
 */
const getStatus = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT premium_until FROM users WHERE id = $1`,
      [req.userId]
    );
    const until = result.rows[0]?.premium_until;
    const active = premium() && until && new Date(until) > new Date();
    return res.json({
      feature_enabled: premium(),
      active: !!active,
      premium_until: until || null,
      benefits: [
        "contacts_illimites",
        "safe_trip_illimite",
        "sms_priority",
      ],
    });
  } catch (err) {
    console.error("premium getStatus error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

/** Grant premium days (platform_admin or self-stub for testing when not production). */
const grantPremium = async (req, res) => {
  if (!premium()) {
    return res.status(503).json({ error: "Premium désactivé (FEATURE_PREMIUM)" });
  }
  const days = Math.min(Math.max(parseInt(req.body.days) || 30, 1), 365);
  const targetId = req.body.user_id || req.userId;

  if (targetId !== req.userId && req.userRole !== "platform_admin") {
    return res.status(403).json({ error: "Admin requis pour attribuer à un tiers" });
  }

  // In production, only platform_admin can grant (no fake self-checkout)
  if (process.env.NODE_ENV === "production" && req.userRole !== "platform_admin") {
    return res.status(403).json({
      error: "Paiement non configuré — contactez l'équipe SafeAlert",
      code: "PAYMENT_NOT_CONFIGURED",
    });
  }

  try {
    const result = await pool.query(
      `UPDATE users SET
         premium_until = GREATEST(COALESCE(premium_until, NOW()), NOW()) + ($2 * INTERVAL '1 day'),
         updated_at = NOW()
       WHERE id = $1
       RETURNING id, premium_until`,
      [targetId, days]
    );
    return res.json({
      message: `Premium accordé pour ${days} jours`,
      user: result.rows[0],
    });
  } catch (err) {
    console.error("grantPremium error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

module.exports = { getStatus, grantPremium };
