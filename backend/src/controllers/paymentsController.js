const { premium } = require("../config/features");
const payHub = require("../services/afrisoftPayHub");
const premiumPayments = require("../services/premiumPayments");
const { pricingWithCdf } = require("../services/premiumEntitlements");
const { fail } = require("../utils/httpError");

const assertPremiumFeature = (res) => {
  if (!premium()) {
    res.status(503).json({ error: "Cette fonction n'est pas encore disponible." });
    return false;
  }
  return true;
};

const respondErr = (res, err, fallback) => {
  const status = err && err.status && Number.isInteger(err.status) ? err.status : null;
  if (status && status >= 400 && status < 500) {
    return res.status(status).json({
      error: err.message || fallback,
      code: err.code || undefined,
    });
  }
  return fail(res, err, fallback);
};

/** GET /api/payments/config */
const getConfig = async (req, res) => {
  const pricing = pricingWithCdf();
  return res.json({
    feature_enabled: premium(),
    afriSoftPayHubEnabled: payHub.isConfigured(),
    mobile_money_available: premium() && payHub.isConfigured(),
    preferred_operators: ["mpesa", "airtel"],
    preferred_telecoms: ["MP", "AM"],
    operators: [
      { id: "mpesa", telecom: "MP", label: "M-Pesa", recommended: true },
      { id: "airtel", telecom: "AM", label: "Airtel Money", recommended: true },
      { id: "orange", telecom: "OM", label: "Orange Money", recommended: false },
    ],
    min_cdf: payHub.MIN_CDF,
    pricing,
    plans: premiumPayments.listPlans(),
  });
};

/** POST /api/payments/premium/intents */
const createIntent = async (req, res) => {
  if (!assertPremiumFeature(res)) return;
  const plan = req.body.plan || req.body.plan_code || "monthly";
  const phone = req.body.phone || req.body.payer_phone || req.body.payerPhoneNumber;
  const telecom =
    req.body.telecom ||
    req.body.operator ||
    req.body.mobile_money_operator ||
    req.body.mobileMoneyOperator ||
    "MP";

  if (!phone) {
    return res.status(400).json({ error: "Numéro Mobile Money requis.", code: "PHONE_REQUIRED" });
  }

  try {
    const intent = await premiumPayments.createIntent({
      userId: req.userId,
      planCode: plan,
      phone,
      telecom,
    });
    return res.status(201).json(intent);
  } catch (err) {
    return respondErr(res, err, "Impossible de créer le paiement.");
  }
};

/** POST /api/payments/premium/intents/:id/start */
const startCharge = async (req, res) => {
  if (!assertPremiumFeature(res)) return;
  try {
    const intent = await premiumPayments.startCharge(req.params.id, req.userId);
    return res.json(intent);
  } catch (err) {
    return respondErr(res, err, "Impossible de démarrer le paiement Mobile Money.");
  }
};

/** GET /api/payments/premium/intents/:id */
const getIntent = async (req, res) => {
  if (!assertPremiumFeature(res)) return;
  try {
    const intent = await premiumPayments.refreshIntentFromHub(
      req.params.id,
      req.userId
    );
    if (!intent) {
      return res.status(404).json({ error: "Paiement introuvable." });
    }
    return res.json(intent);
  } catch (err) {
    return respondErr(res, err, "Impossible de charger le paiement.");
  }
};

/** POST /api/premium/mobile-money — create + start in one call */
const startMobileMoney = async (req, res) => {
  if (!assertPremiumFeature(res)) return;
  if (!payHub.isConfigured()) {
    return res.status(503).json({
      error: "Paiement Mobile Money non configuré.",
      code: "PAY_HUB_NOT_CONFIGURED",
    });
  }

  const plan = req.body.plan || req.body.plan_code || "monthly";
  const phone = req.body.phone || req.body.payer_phone;
  const telecom = req.body.telecom || req.body.operator || "MP";

  if (!phone) {
    return res.status(400).json({ error: "Numéro Mobile Money requis.", code: "PHONE_REQUIRED" });
  }

  try {
    const intent = await premiumPayments.startMobileMoneyCheckout({
      userId: req.userId,
      planCode: plan,
      phone,
      telecom,
    });
    return res.status(201).json(intent);
  } catch (err) {
    return respondErr(res, err, "Impossible de démarrer le paiement Mobile Money.");
  }
};

/** GET /api/premium/payments/:id */
const getPaymentStatus = async (req, res) => getIntent(req, res);

/** GET /api/premium/plans */
const listPlans = async (req, res) => {
  return res.json({
    plans: premiumPayments.listPlans(),
    mobile_money_available: payHub.isConfigured() && premium(),
    preferred_telecoms: ["MP", "AM"],
    telecoms: [
      { code: "MP", label: "M-Pesa", recommended: true },
      { code: "AM", label: "Airtel Money", recommended: true },
      { code: "OM", label: "Orange Money", recommended: false },
    ],
    min_cdf: payHub.MIN_CDF,
  });
};

module.exports = {
  getConfig,
  createIntent,
  startCharge,
  getIntent,
  startMobileMoney,
  getPaymentStatus,
  listPlans,
};
