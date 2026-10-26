/**
 * Free vs Premium entitlements (see docs/ECONOMIE.md).
 * Defaults are hardcoded; admins can override via app_settings (CRUD console).
 * When FEATURE_PREMIUM is off, callers should skip soft limits (legacy behaviour).
 */

const { pool } = require("../config/database");
const { premium } = require("../config/features");
const { hubConfigured } = require("./afrisoftPayHub");

const KEY_FREE = "premium_plan_free";
const KEY_PREMIUM = "premium_plan_premium";
const KEY_PRICING = "premium_pricing";

const PRICING_DEFAULT = {
  currency: "USD",
  monthly_usd: 2,
  yearly_usd: 20,
  monthly_cdf_approx: 5500,
  yearly_cdf_approx: 55000,
};

const FREE_DEFAULT = {
  contacts_max: 5,
  trips_per_week: 3,
  trip_eta_max_minutes: 120,
  history_limit: 30,
  sos_priority: false,
  sos_mediation: false,
  live_circles_max: 1,
};

const PREMIUM_DEFAULT = {
  contacts_max: 25,
  trips_per_week: null, // unlimited
  trip_eta_max_minutes: 12 * 60,
  history_limit: 100,
  sos_priority: true,
  sos_mediation: true,
  live_circles_max: 5,
};

/** Legacy caps when monetization flag is off. */
const LEGACY = {
  contacts_max: 10,
  trips_per_week: null,
  trip_eta_max_minutes: 24 * 60,
  history_limit: 100,
  sos_priority: false,
  sos_mediation: true,
  live_circles_max: 5,
};

/** @deprecated use FREE_DEFAULT — kept for require() callers */
const FREE = FREE_DEFAULT;
/** @deprecated use PREMIUM_DEFAULT */
const PREMIUM = PREMIUM_DEFAULT;
/** @deprecated use getPricingSync() */
const PRICING = PRICING_DEFAULT;

const BENEFIT_KEYS = [
  "trajets_illimites",
  "eta_long",
  "contacts_elargis",
  "historique_etendu",
  "sos_prioritaire",
  "sos_mediation",
  "live_circles",
];

const ENTITLEMENT_FIELDS = [
  "contacts_max",
  "trips_per_week",
  "trip_eta_max_minutes",
  "history_limit",
  "sos_priority",
  "sos_mediation",
  "live_circles_max",
];

let planCache = {
  at: 0,
  free: { ...FREE_DEFAULT },
  premium: { ...PREMIUM_DEFAULT },
  pricing: { ...PRICING_DEFAULT },
};

const usdToCdfRate = () => {
  const n = Number(process.env.USD_TO_CDF_RATE || 2850);
  return Number.isFinite(n) && n > 0 ? n : 2850;
};

/** max(2300, ceil(usd * rate)) — SerdiPay floor. */
const toCdf = (amountUsd, rate = usdToCdfRate()) => {
  const usd = Number(amountUsd);
  if (!Number.isFinite(usd) || usd < 0) return 2300;
  return Math.max(2300, Math.ceil(usd * rate));
};

function clampInt(v, { min = 0, max = 1e6, fallback = 0, allowNull = false } = {}) {
  if (v === null || v === undefined || v === "") {
    return allowNull ? null : fallback;
  }
  const n = Number(v);
  if (!Number.isFinite(n)) return allowNull ? null : fallback;
  return Math.min(max, Math.max(min, Math.round(n)));
}

function normalizeEntitlements(raw, defaults) {
  const src = raw && typeof raw === "object" ? raw : {};
  return {
    contacts_max: clampInt(src.contacts_max, {
      min: 1,
      max: 500,
      fallback: defaults.contacts_max,
    }),
    trips_per_week:
      src.trips_per_week === null || src.trips_per_week === "null" || src.trips_per_week === ""
        ? null
        : clampInt(src.trips_per_week, {
            min: 0,
            max: 1000,
            fallback: defaults.trips_per_week ?? 3,
            allowNull: true,
          }),
    trip_eta_max_minutes: clampInt(src.trip_eta_max_minutes, {
      min: 15,
      max: 24 * 60,
      fallback: defaults.trip_eta_max_minutes,
    }),
    history_limit: clampInt(src.history_limit, {
      min: 5,
      max: 5000,
      fallback: defaults.history_limit,
    }),
    sos_priority: Boolean(src.sos_priority),
    sos_mediation: Boolean(src.sos_mediation),
    live_circles_max: clampInt(src.live_circles_max, {
      min: 0,
      max: 50,
      fallback: defaults.live_circles_max,
    }),
  };
}

function normalizePricing(raw) {
  const src = raw && typeof raw === "object" ? raw : {};
  const monthly_usd = Number(src.monthly_usd);
  const yearly_usd = Number(src.yearly_usd);
  return {
    currency: "USD",
    monthly_usd:
      Number.isFinite(monthly_usd) && monthly_usd >= 0
        ? Math.round(monthly_usd * 100) / 100
        : PRICING_DEFAULT.monthly_usd,
    yearly_usd:
      Number.isFinite(yearly_usd) && yearly_usd >= 0
        ? Math.round(yearly_usd * 100) / 100
        : PRICING_DEFAULT.yearly_usd,
  };
}

async function readSettingJson(key) {
  try {
    const r = await pool.query(`SELECT value FROM app_settings WHERE key = $1 LIMIT 1`, [key]);
    if (!r.rows[0]?.value) return null;
    return JSON.parse(r.rows[0].value);
  } catch (err) {
    if (err.code !== "42P01") {
      console.error(`premiumEntitlements read ${key}:`, err.message);
    }
    return null;
  }
}

async function writeSettingJson(key, value) {
  await pool.query(
    `INSERT INTO app_settings (key, value, updated_at)
     VALUES ($1, $2, NOW())
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`,
    [key, JSON.stringify(value)]
  );
}

async function loadPlanConfig(force = false) {
  if (!force && planCache.at && Date.now() - planCache.at < 15000) {
    return planCache;
  }
  const [freeRaw, premRaw, priceRaw] = await Promise.all([
    readSettingJson(KEY_FREE),
    readSettingJson(KEY_PREMIUM),
    readSettingJson(KEY_PRICING),
  ]);
  planCache = {
    at: Date.now(),
    free: normalizeEntitlements(freeRaw, FREE_DEFAULT),
    premium: normalizeEntitlements(premRaw, PREMIUM_DEFAULT),
    pricing: normalizePricing(priceRaw || PRICING_DEFAULT),
  };
  // Keep deprecated sync exports roughly in sync for old require sites
  Object.assign(FREE, planCache.free);
  Object.assign(PREMIUM, planCache.premium);
  Object.assign(PRICING, planCache.pricing);
  return planCache;
}

function pricingWithCdf(pricing = planCache.pricing) {
  const base = normalizePricing(pricing);
  const rate = usdToCdfRate();
  const monthly_cdf = toCdf(base.monthly_usd, rate);
  const yearly_cdf = toCdf(base.yearly_usd, rate);
  return {
    ...base,
    usd_to_cdf_rate: rate,
    monthly_cdf,
    yearly_cdf,
    monthly_cdf_approx: monthly_cdf,
    yearly_cdf_approx: yearly_cdf,
  };
}

async function getPlansAdminPayload() {
  const cfg = await loadPlanConfig(true);
  return {
    free: cfg.free,
    premium: cfg.premium,
    pricing: pricingWithCdf(cfg.pricing),
    defaults: {
      free: { ...FREE_DEFAULT },
      premium: { ...PREMIUM_DEFAULT },
      pricing: pricingWithCdf(PRICING_DEFAULT),
    },
    field_hints: {
      contacts_max: "Nombre max de contacts de confiance",
      trips_per_week: "Trajets sécurisés / semaine (vide = illimité)",
      trip_eta_max_minutes: "Durée max d'un trajet (minutes)",
      history_limit: "Entrées d'historique visibles",
      sos_priority: "Priorité SOS (file partenaires)",
      sos_mediation: "Médiation SOS",
      live_circles_max: "Cercles live max",
      monthly_usd: "Prix mensuel USD",
      yearly_usd: "Prix annuel USD",
    },
  };
}

async function savePlansAdmin({ free, premium: prem, pricing }) {
  const nextFree = normalizeEntitlements(free, FREE_DEFAULT);
  const nextPrem = normalizeEntitlements(prem, PREMIUM_DEFAULT);
  const nextPrice = normalizePricing(pricing);
  await writeSettingJson(KEY_FREE, nextFree);
  await writeSettingJson(KEY_PREMIUM, nextPrem);
  await writeSettingJson(KEY_PRICING, nextPrice);
  planCache = {
    at: Date.now(),
    free: nextFree,
    premium: nextPrem,
    pricing: nextPrice,
  };
  Object.assign(FREE, nextFree);
  Object.assign(PREMIUM, nextPrem);
  Object.assign(PRICING, nextPrice);
  return getPlansAdminPayload();
}

async function resetPlansAdmin() {
  await writeSettingJson(KEY_FREE, FREE_DEFAULT);
  await writeSettingJson(KEY_PREMIUM, PREMIUM_DEFAULT);
  await writeSettingJson(KEY_PRICING, {
    currency: "USD",
    monthly_usd: PRICING_DEFAULT.monthly_usd,
    yearly_usd: PRICING_DEFAULT.yearly_usd,
  });
  return savePlansAdmin({
    free: FREE_DEFAULT,
    premium: PREMIUM_DEFAULT,
    pricing: PRICING_DEFAULT,
  });
}

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

const entitlementsFor = (isPremiumActive, cfg = planCache) => {
  if (!premium()) return { ...LEGACY, tier: "legacy" };
  if (isPremiumActive) return { ...cfg.premium, tier: "premium" };
  return { ...cfg.free, tier: "free" };
};

const getEntitlementsForUser = async (userId) => {
  const cfg = await loadPlanConfig();
  const active = await userIsPremium(userId);
  return entitlementsFor(active, cfg);
};

const getStatusPayload = async (userId) => {
  const cfg = await loadPlanConfig();
  const until = await getPremiumUntil(userId);
  const active = premium() && until && new Date(until) > new Date();
  const entitlements = entitlementsFor(!!active, cfg);
  const pricing = pricingWithCdf(cfg.pricing);
  return {
    feature_enabled: premium(),
    active: !!active,
    premium_until: until || null,
    pricing,
    entitlements,
    benefits: BENEFIT_KEYS,
    test_purchase_allowed: premium() && allowTestPurchase(),
    checkout_available: premium() && (stripeConfigured() || hubConfigured()),
    mobile_money_available: premium() && hubConfigured(),
    afriSoftPayHubEnabled: hubConfigured(),
    preferred_operators: ["mpesa", "airtel"],
    preferred_telecoms: ["MP", "AM"],
  };
};

// Warm cache (non-blocking)
loadPlanConfig().catch(() => {});

module.exports = {
  PRICING,
  FREE,
  PREMIUM,
  FREE_DEFAULT,
  PREMIUM_DEFAULT,
  PRICING_DEFAULT,
  LEGACY,
  BENEFIT_KEYS,
  ENTITLEMENT_FIELDS,
  partnerPlanFromRateLimit,
  stripeConfigured,
  allowTestPurchase,
  userIsPremium,
  getPremiumUntil,
  entitlementsFor,
  getEntitlementsForUser,
  getStatusPayload,
  usdToCdfRate,
  toCdf,
  pricingWithCdf,
  loadPlanConfig,
  getPlansAdminPayload,
  savePlansAdmin,
  resetPlansAdmin,
};
