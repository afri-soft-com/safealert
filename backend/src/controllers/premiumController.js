const { pool } = require("../config/database");
const { premium } = require("../config/features");
const {
  getStatusPayload,
  allowTestPurchase,
  stripeConfigured,
} = require("../services/premiumEntitlements");

/**
 * Premium — entitlements + grant/revoke + Stripe Checkout stub.
 * See docs/ECONOMIE.md. No fake Stripe secrets.
 */
const getStatus = async (req, res) => {
  try {
    const payload = await getStatusPayload(req.userId);
    return res.json(payload);
  } catch (err) {
    console.error("premium getStatus error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const assertPremiumFeature = (res) => {
  if (!premium()) {
    res.status(503).json({ error: "Premium désactivé (FEATURE_PREMIUM)" });
    return false;
  }
  return true;
};

const canSelfGrant = (req) => {
  if (req.userRole === "platform_admin") return true;
  return allowTestPurchase();
};

/** Grant premium days (admin any user; self only if test purchase allowed). */
const grantPremium = async (req, res) => {
  const days = Math.min(Math.max(parseInt(req.body.days, 10) || 30, 1), 365);
  const targetId = req.body.user_id || req.userId;

  if (targetId !== req.userId && req.userRole !== "platform_admin") {
    return res.status(403).json({ error: "Admin requis pour attribuer à un tiers" });
  }

  if (targetId === req.userId && req.userRole !== "platform_admin") {
    if (!assertPremiumFeature(res)) return;
    if (!canSelfGrant(req)) {
      return res.status(403).json({
        error: "Paiement non configuré — contactez l'équipe SafeAlert",
        code: "PAYMENT_NOT_CONFIGURED",
      });
    }
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
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Utilisateur non trouvé" });
    }
    return res.json({
      message: `Premium accordé pour ${days} jours`,
      user: result.rows[0],
    });
  } catch (err) {
    console.error("grantPremium error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

/** Revoke premium (platform_admin only). */
const revokePremium = async (req, res) => {
  if (req.userRole !== "platform_admin") {
    return res.status(403).json({ error: "Admin requis" });
  }

  const targetId = req.body.user_id || req.params.userId;
  if (!targetId) {
    return res.status(400).json({ error: "user_id requis" });
  }

  try {
    const result = await pool.query(
      `UPDATE users SET premium_until = NULL, updated_at = NOW()
       WHERE id = $1
       RETURNING id, premium_until`,
      [targetId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Utilisateur non trouvé" });
    }
    return res.json({
      message: "Premium révoqué",
      user: result.rows[0],
    });
  } catch (err) {
    console.error("revokePremium error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

/**
 * Stripe Checkout stub — returns checkout_available=false without real keys.
 * Never invents secrets. When keys exist, returns a placeholder URL shape
 * for a future real session (still no charge without Stripe SDK wiring).
 */
const createCheckout = async (req, res) => {
  if (!assertPremiumFeature(res)) return;

  if (!stripeConfigured()) {
    return res.json({
      checkout_available: false,
      mode: "stub",
      message:
        "Stripe non configuré. Utilisez l'activation test ou demandez un grant admin.",
      test_purchase_allowed: allowTestPurchase(),
      checkout_url: null,
    });
  }

  // Keys present: stub session metadata only (real Stripe SDK not required for MVP).
  const success =
    process.env.STRIPE_SUCCESS_URL ||
    "https://safealert-api.onrender.com/premium/success";
  const cancel =
    process.env.STRIPE_CANCEL_URL ||
    "https://safealert-api.onrender.com/premium/cancel";

  return res.json({
    checkout_available: true,
    mode: "stripe_stub",
    message:
      "Clés Stripe détectées — branchez le SDK Checkout pour créer une session réelle.",
    price_id: process.env.STRIPE_PRICE_ID_PREMIUM,
    success_url: success,
    cancel_url: cancel,
    checkout_url: null,
  });
};

module.exports = { getStatus, grantPremium, revokePremium, createCheckout };
