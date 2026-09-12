/**
 * Premium Mobile Money payment intents + webhook completion.
 * Table: premium_payment_intents (see migrate.js).
 */
const crypto = require("crypto");
const { pool } = require("../config/database");
const payHub = require("./afrisoftPayHub");
const platformWallet = require("./platformWallet");
const { PRICING, pricingWithCdf, toCdf } = require("./premiumEntitlements");
const { warn } = require("../utils/logger");

const PLANS = {
  monthly: {
    code: "monthly",
    label: "Premium mensuel",
    days: 30,
    amount_usd: PRICING.monthly_usd,
  },
  yearly: {
    code: "yearly",
    label: "Premium annuel",
    days: 365,
    amount_usd: PRICING.yearly_usd,
  },
};

function resolvePlan(planCode) {
  const key = String(planCode || "monthly")
    .trim()
    .toLowerCase();
  const plan = PLANS[key];
  if (!plan) {
    const err = new Error("Plan invalide (monthly | yearly).");
    err.status = 400;
    err.code = "INVALID_PLAN";
    throw err;
  }
  return plan;
}

async function grantPremiumDays(userId, days, client = pool) {
  const result = await client.query(
    `UPDATE users SET
       premium_until = GREATEST(COALESCE(premium_until, NOW()), NOW()) + ($2 * INTERVAL '1 day'),
       updated_at = NOW()
     WHERE id = $1
     RETURNING id, premium_until`,
    [userId, days]
  );
  return result.rows[0] || null;
}

function mapIntentPublic(row, extras = {}) {
  if (!row) return null;
  return {
    id: row.id,
    status: String(row.status || "").toLowerCase(),
    plan: row.plan,
    amount_usd: Number(row.amount_usd),
    amount_cdf: Number(row.amount_cdf),
    days: row.days,
    currency: "CDF",
    telecom: row.telecom,
    payer_phone: row.payer_phone,
    hub_reference: row.hub_reference,
    external_reference: row.external_reference,
    message:
      row.status === "pending"
        ? extras.message ||
          "Confirmez le paiement sur votre téléphone Mobile Money."
        : row.failure_reason || null,
    payment_url: extras.payment_url || null,
    mobile_money_live_pending: row.status === "pending" && !!row.external_reference,
    live_pending: row.status === "pending" && !!row.external_reference,
    failure_reason: row.failure_reason,
    completed_at: row.completed_at,
    created_at: row.created_at,
    ...extras.premium_until != null
      ? { premium_until: extras.premium_until }
      : {},
  };
}

/** Create pending intent (no hub call yet). */
async function createIntent({
  userId,
  planCode,
  phone,
  telecom,
}) {
  if (!payHub.isConfigured()) {
    const err = new Error("Paiement Mobile Money non configuré.");
    err.status = 503;
    err.code = "PAY_HUB_NOT_CONFIGURED";
    throw err;
  }

  const plan = resolvePlan(planCode);
  const pricing = pricingWithCdf();
  const amountCdf =
    plan.code === "yearly" ? pricing.yearly_cdf : pricing.monthly_cdf;
  const telecomCode = payHub.operatorToTelecom(telecom || "MP");
  const phoneNorm = payHub.normalizeHubPhone(phone);
  const intentId = crypto.randomUUID();
  const app = payHub.appId() || "safealert";
  const hubReference = `${app}_premium_${intentId}`;

  await pool.query(
    `INSERT INTO premium_payment_intents
       (id, user_id, plan, amount_usd, amount_cdf, days, method, telecom,
        payer_phone, status, hub_reference, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, 'mobile_money', $7,
             $8, 'pending', $9, NOW(), NOW())`,
    [
      intentId,
      userId,
      plan.code,
      plan.amount_usd,
      amountCdf,
      plan.days,
      telecomCode,
      phoneNorm,
      hubReference,
    ]
  );

  const row = await getIntentRow(intentId);
  return mapIntentPublic(row);
}

async function getIntentRow(intentId) {
  const r = await pool.query(
    `SELECT * FROM premium_payment_intents WHERE id = $1`,
    [intentId]
  );
  return r.rows[0] || null;
}

async function getIntentForUser(intentId, userId) {
  const r = await pool.query(
    `SELECT * FROM premium_payment_intents WHERE id = $1 AND user_id = $2`,
    [intentId, userId]
  );
  return r.rows[0] || null;
}

/**
 * Start hub C2B for an existing pending intent.
 */
async function startCharge(intentId, userId) {
  const row = await getIntentForUser(intentId, userId);
  if (!row) {
    const err = new Error("Paiement introuvable.");
    err.status = 404;
    throw err;
  }
  if (row.status === "completed") {
    return mapIntentPublic(row);
  }
  if (row.status !== "pending") {
    const err = new Error("Ce paiement ne peut plus être démarré.");
    err.status = 400;
    throw err;
  }

  // Already started — return current + optional poll
  if (row.external_reference) {
    return refreshIntentFromHub(intentId, userId);
  }

  const app = payHub.appId() || "safealert";
  const hub = await payHub.createPayment({
    amountCdf: row.amount_cdf,
    phone: row.payer_phone,
    telecom: row.telecom,
    reference: row.hub_reference,
    purpose: "premium",
    idempotencyKey: `${app}:premium:${row.id.replace(/-/g, "")}`,
    metadata: {
      intent_id: row.id,
      user_id: userId,
      plan: row.plan,
      days: row.days,
    },
  });

  if (!hub.ok) {
    await pool.query(
      `UPDATE premium_payment_intents
       SET status = 'failed', failure_reason = $2, completed_at = NOW(), updated_at = NOW()
       WHERE id = $1`,
      [row.id, hub.error || "Initiation échouée"]
    );
    const err = new Error(hub.error || "Impossible de démarrer le paiement.");
    err.status = 400;
    err.code = "PAY_HUB_INIT_FAILED";
    throw err;
  }

  await pool.query(
    `UPDATE premium_payment_intents
     SET external_reference = $2, updated_at = NOW()
     WHERE id = $1`,
    [row.id, hub.payment_id]
  );

  const fresh = await getIntentRow(row.id);
  return mapIntentPublic(fresh, {
    message: hub.message,
    payment_url: hub.payment_url,
  });
}

/**
 * One-shot: create intent + start charge (used by /premium/mobile-money).
 */
async function startMobileMoneyCheckout({ userId, planCode, phone, telecom }) {
  const intent = await createIntent({ userId, planCode, phone, telecom });
  return startCharge(intent.id, userId);
}

async function refreshIntentFromHub(intentId, userId) {
  const row = await getIntentForUser(intentId, userId);
  if (!row) return null;
  if (row.status !== "pending") {
    let premiumUntil = null;
    if (row.status === "completed") {
      const u = await pool.query(`SELECT premium_until FROM users WHERE id = $1`, [
        row.user_id,
      ]);
      premiumUntil = u.rows[0]?.premium_until || null;
    }
    return mapIntentPublic(row, { premium_until: premiumUntil });
  }
  if (!row.external_reference) return mapIntentPublic(row);

  const remote = await payHub.getPayment(row.external_reference);
  if (!remote) return mapIntentPublic(row);

  if (String(remote.status).toUpperCase() === "COMPLETED") {
    await completeIntent({
      intentRow: row,
      paymentId: remote.payment_id || row.external_reference,
      amountCdf: remote.amount_cdf,
    });
    const fresh = await getIntentForUser(intentId, userId);
    const u = await pool.query(`SELECT premium_until FROM users WHERE id = $1`, [
      userId,
    ]);
    return mapIntentPublic(fresh, {
      premium_until: u.rows[0]?.premium_until || null,
    });
  }
  if (String(remote.status).toUpperCase() === "FAILED") {
    await pool.query(
      `UPDATE premium_payment_intents
       SET status = 'failed', failure_reason = $2, completed_at = NOW(), updated_at = NOW()
       WHERE id = $1 AND status = 'pending'`,
      [row.id, "Paiement Mobile Money échoué"]
    );
    const fresh = await getIntentForUser(intentId, userId);
    return mapIntentPublic(fresh);
  }
  return mapIntentPublic(row);
}

async function completeIntent({ intentRow, paymentId, amountCdf }) {
  if (!intentRow || intentRow.status === "completed") return intentRow;

  const expected = Number(intentRow.amount_cdf);
  if (
    amountCdf != null &&
    Number.isFinite(Number(amountCdf)) &&
    Math.abs(Number(amountCdf) - expected) > 1
  ) {
    warn(
      "Pay hub amount mismatch",
      intentRow.id,
      "got",
      amountCdf,
      "expected",
      expected
    );
    await pool.query(
      `UPDATE premium_payment_intents
       SET status = 'failed', failure_reason = $2, completed_at = NOW(), updated_at = NOW()
       WHERE id = $1 AND status = 'pending'`,
      [intentRow.id, "Montant incohérent — paiement refusé"]
    );
    return null;
  }

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const locked = await client.query(
      `SELECT * FROM premium_payment_intents WHERE id = $1 FOR UPDATE`,
      [intentRow.id]
    );
    const row = locked.rows[0];
    if (!row || row.status === "completed") {
      await client.query("COMMIT");
      return row;
    }
    if (row.status !== "pending") {
      await client.query("COMMIT");
      return row;
    }

    await grantPremiumDays(row.user_id, row.days || 30, client);
    await client.query(
      `UPDATE premium_payment_intents
       SET status = 'completed',
           external_reference = COALESCE($2, external_reference),
           completed_at = NOW(),
           updated_at = NOW()
       WHERE id = $1`,
      [row.id, paymentId || null]
    );
    await client.query("COMMIT");
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }

  await platformWallet.creditFromPaymentIntent({
    paymentIntentId: intentRow.id,
    amountCdf: expected,
    externalReference:
      paymentId || intentRow.external_reference || intentRow.hub_reference,
    reason:
      intentRow.plan === "yearly"
        ? "Abonnement Premium annuel"
        : "Abonnement Premium mensuel",
  });

  return getIntentRow(intentRow.id);
}

async function findIntentByHubRefs(paymentId, reference) {
  if (paymentId) {
    const byPay = await pool.query(
      `SELECT * FROM premium_payment_intents WHERE external_reference = $1 LIMIT 1`,
      [paymentId]
    );
    if (byPay.rows[0]) return byPay.rows[0];
  }
  if (reference) {
    const byRef = await pool.query(
      `SELECT * FROM premium_payment_intents WHERE hub_reference = $1 LIMIT 1`,
      [reference]
    );
    if (byRef.rows[0]) return byRef.rows[0];
    const m = String(reference).match(/_premium_([0-9a-f-]{36})$/i);
    if (m) {
      const byId = await pool.query(
        `SELECT * FROM premium_payment_intents WHERE id = $1 LIMIT 1`,
        [m[1]]
      );
      if (byId.rows[0]) return byId.rows[0];
    }
  }
  return null;
}

async function processWebhook({ rawBody, timestamp, signature, path }) {
  if (!payHub.isConfigured()) {
    return { ok: true, code: "ignored_unconfigured" };
  }
  const valid = payHub.verifyIncomingWebhook(
    timestamp,
    signature,
    path || "/webhooks/afrisoft-payments",
    rawBody
  );
  if (!valid) {
    return { ok: false, code: "invalid_signature" };
  }

  let payload;
  try {
    payload = JSON.parse(rawBody || "{}");
  } catch {
    return { ok: true, code: "ignored_bad_json" };
  }

  const status = String(payload.status || "").toUpperCase();
  const eventName = String(payload.event || "").toLowerCase();
  const paymentId = payload.payment_id || null;
  const reference = payload.reference || null;
  const purpose = String(payload.purpose || "").toLowerCase();
  const amountCdf = payload.amount_cdf;

  const isWithdraw =
    purpose === "withdraw" ||
    (reference && String(reference).includes("_withdraw_"));

  if (isWithdraw) {
    const success =
      status === "COMPLETED" || eventName === "payment.completed";
    const failed = status === "FAILED" || eventName === "payment.failed";
    if (success || failed) {
      await platformWallet.applyPayoutWebhook({
        externalReference: paymentId || reference,
        success,
        failureReason: payload.failure_reason || null,
      });
    }
    return { ok: true, code: "processed_payout" };
  }

  const row = await findIntentByHubRefs(paymentId, reference);
  if (!row) {
    return { ok: true, code: "ignored_unknown_intent" };
  }

  if (status === "FAILED" || eventName === "payment.failed") {
    if (row.status === "pending") {
      await pool.query(
        `UPDATE premium_payment_intents
         SET status = 'failed',
             failure_reason = $2,
             completed_at = NOW(),
             updated_at = NOW()
         WHERE id = $1 AND status = 'pending'`,
        [row.id, payload.failure_reason || "Paiement Mobile Money échoué"]
      );
    }
    return { ok: true, code: "processed_failed" };
  }

  if (status !== "COMPLETED" && eventName !== "payment.completed") {
    return { ok: true, code: "ignored_non_final" };
  }

  await completeIntent({
    intentRow: row,
    paymentId: paymentId || row.external_reference,
    amountCdf,
  });
  return { ok: true, code: "processed_completed" };
}

function listPlans() {
  const pricing = pricingWithCdf();
  return Object.values(PLANS).map((p) => ({
    code: p.code,
    label: p.label,
    days: p.days,
    amount_usd: p.amount_usd,
    amount_cdf: p.code === "yearly" ? pricing.yearly_cdf : pricing.monthly_cdf,
  }));
}

module.exports = {
  PLANS,
  resolvePlan,
  listPlans,
  createIntent,
  startCharge,
  startMobileMoneyCheckout,
  getIntentForUser,
  mapIntentPublic,
  refreshIntentFromHub,
  processWebhook,
  completeIntent,
  grantPremiumDays,
  toCdf,
};
