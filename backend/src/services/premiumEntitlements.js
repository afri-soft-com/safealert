/**
 * Free vs Premium entitlements (see docs/ECONOMIE.md).
 * When FEATURE_PREMIUM is off, callers should skip soft limits (legacy behaviour).
 */

const { pool } = require("../config/database");
const { premium } = require("../config/features");

const PRICING = {
  currency: "USD",
  monthly_usd: 2,
  yearly_usd: 20,
  monthly_cdf_approx: 5500,
  yearly_cdf_approx: 55000,
};

const FREE = {
  contacts_max: 5,
  trips_per_week: 3,
  trip_eta_max_minutes: 120,
  history_limit: 30,
  sos_priority: false,
};

const PREMIUM = {
  contacts_max: 25,
  trips_per_week: null, // unlimited
  trip_eta_max_minutes: 12 * 60,
  history_limit: 100,
  sos_priority: true,
};

/** Legacy caps when monetization flag is off. */
const LEGACY = {
  contacts_max: 10,
  trips_per_week: null,
  trip_eta_max_minutes: 24 * 60,
  history_limit: 100,
  sos_priority: false,
};

const BENEFIT_KEYS = [
  "trajets_illimites",
  "eta_long",
  "contacts_elargis",
  "historique_etendu",
  "sos_prioritaire",
];

const partnerPlanFromRateLimit = (rateLimit) => {
  const n = Math.max(1, Number(rateLimit) || 1000);
  if (n <= 500) {
    return { code: "essai", label: "Essai", price_usd: 0, rate_limit: n };
  }
  if (n <= 1000) {
    return { code: "standard", label: "Standard", price_usd: 50, rate_limit: n };
  }
  if (n <= 5000) {
    return { code: "pro", label: "Pro", price_usd: 100, rate_limit: n };
  }
  return { code: "enterprise", label: "Entreprise", price_usd: null, rate_limit: n };
};

const stripeConfigured = () =>
  Boolean(
    process.env.STRIPE_SECRET_KEY &&
      String(process.env.STRIPE_SECRET_KEY).trim() &&
      process.env.STRIPE_PRICE_ID_PREMIUM &&
      String(process.env.STRIPE_PRICE_ID_PREMIUM).trim()
  );

/** Testers may self-activate without Stripe. */
const allowTestPurchase = () => {
  const raw = process.env.FEATURE_PREMIUM_TEST_PURCHASE;
  if (raw !== undefined && raw !== "") {
    return ["1", "true", "yes", "on"].includes(String(raw).toLowerCase());
  }
  if (
    process.env.ALLOW_DEV_OTP === "true" ||
    process.env.OTP_BYPASS_ENABLED === "true"
  ) {
    return true;
  }
  return process.env.NODE_ENV !== "production";
};

const userIsPremium = async (userId) => {
  if (!premium()) return false;
  const r = await pool.query(
    `SELECT premium_until FROM users WHERE id = $1 AND premium_until > NOW()`,
    [userId]
  );
  return r.rows.length > 0;
};

const getPremiumUntil = async (userId) => {
  const r = await pool.query(`SELECT premium_until FROM users WHERE id = $1`, [userId]);
  return r.rows[0]?.premium_until || null;
};

const entitlementsFor = (isPremiumActive) => {
  if (!premium()) return { ...LEGACY, tier: "legacy" };
  if (isPremiumActive) return { ...PREMIUM, tier: "premium" };
  return { ...FREE, tier: "free" };
};

const getEntitlementsForUser = async (userId) => {
  const active = await userIsPremium(userId);
  return entitlementsFor(active);
};

const getStatusPayload = async (userId) => {
  const until = await getPremiumUntil(userId);
  const active = premium() && until && new Date(until) > new Date();
  const entitlements = entitlementsFor(!!active);
  return {
    feature_enabled: premium(),
    active: !!active,
    premium_until: until || null,
    pricing: PRICING,
    entitlements,
    benefits: BENEFIT_KEYS,
    test_purchase_allowed: premium() && allowTestPurchase(),
    checkout_available: premium() && stripeConfigured(),
  };
};

module.exports = {
  PRICING,
  FREE,
  PREMIUM,
  LEGACY,
  BENEFIT_KEYS,
  partnerPlanFromRateLimit,
  stripeConfigured,
  allowTestPurchase,
  userIsPremium,
  getPremiumUntil,
  entitlementsFor,
  getEntitlementsForUser,
  getStatusPayload,
};
