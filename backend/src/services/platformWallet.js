/**
 * Platform treasury wallet — credits from completed C2B, debit via hub B2C withdraw.
 * Tables: platform_wallet, platform_wallet_ledger, platform_wallet_withdrawals.
 */
const crypto = require("crypto");
const { pool } = require("../config/database");
const payHub = require("./afrisoftPayHub");

/** Singleton wallet id (stable UUID). */
const WALLET_ID = "a11ce000-0000-4000-8000-00safealert01";

async function ensureWallet(client = pool) {
  await client.query(
    `INSERT INTO platform_wallet (id, balance_cdf, updated_at)
     VALUES ($1, 0, NOW())
     ON CONFLICT (id) DO NOTHING`,
    [WALLET_ID]
  );
  const r = await client.query(
    `SELECT id, balance_cdf, updated_at FROM platform_wallet WHERE id = $1`,
    [WALLET_ID]
  );
  return r.rows[0];
}

async function getSnapshot() {
  const w = await ensureWallet();
  return {
    balance_cdf: Number(w.balance_cdf),
    updated_at: w.updated_at,
  };
}

async function creditFromPaymentIntent({
  paymentIntentId,
  amountCdf,
  externalReference,
  reason,
}) {
  const amount = Math.round(Number(amountCdf));
  if (!Number.isFinite(amount) || amount <= 0) return;

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const exists = await client.query(
      `SELECT 1 FROM platform_wallet_ledger
       WHERE payment_intent_id = $1 AND direction = 'CREDIT' LIMIT 1`,
      [paymentIntentId]
    );
    if (exists.rowCount > 0) {
      await client.query("COMMIT");
      return;
    }
    const wallet = await ensureWallet(client);
    const next = Number(wallet.balance_cdf) + amount;
    await client.query(
      `UPDATE platform_wallet SET balance_cdf = $2, updated_at = NOW() WHERE id = $1`,
      [WALLET_ID, next]
    );
    await client.query(
      `INSERT INTO platform_wallet_ledger
         (id, wallet_id, direction, amount_cdf, balance_after_cdf, reason,
          payment_intent_id, external_reference, created_at)
       VALUES ($1, $2, 'CREDIT', $3, $4, $5, $6, $7, NOW())`,
      [
        crypto.randomUUID(),
        WALLET_ID,
        amount,
        next,
        reason || "Paiement Premium",
        paymentIntentId,
        externalReference || null,
      ]
    );
    await client.query("COMMIT");
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }
}

async function listLedger(limit = 40) {
  const r = await pool.query(
    `SELECT id, direction, amount_cdf, balance_after_cdf, reason,
            payment_intent_id, external_reference, created_at
     FROM platform_wallet_ledger
     WHERE wallet_id = $1
     ORDER BY created_at DESC
     LIMIT $2`,
    [WALLET_ID, Math.min(Math.max(Number(limit) || 40, 1), 200)]
  );
  return r.rows;
}

async function listWithdrawals(limit = 40) {
  const r = await pool.query(
    `SELECT id, amount_cdf, telecom, destination_phone, status,
            external_reference, failure_reason, requested_by AS requested_by_user_id,
            created_at, completed_at
     FROM platform_wallet_withdrawals
     ORDER BY created_at DESC
     LIMIT $1`,
    [Math.min(Math.max(Number(limit) || 40, 1), 200)]
  );
  return r.rows;
}

async function requestWithdraw({
  adminUserId,
  amountCdf,
  telecom,
  destinationPhone,
}) {
  if (!payHub.isConfigured()) {
    const err = new Error("Hub Mobile Money non configuré.");
    err.status = 503;
    err.code = "PAY_HUB_NOT_CONFIGURED";
    throw err;
  }

  const amount = Math.round(Number(amountCdf));
  if (!Number.isFinite(amount) || amount < payHub.MIN_CDF) {
    const err = new Error(`Retrait minimum : ${payHub.MIN_CDF} FC.`);
    err.status = 400;
    throw err;
  }

  const telecomCode = payHub.normalizeTelecom(telecom);
  const phone = payHub.normalizeHubPhone(destinationPhone);
  const withdrawalId = crypto.randomUUID();
  const reference = `safealert_withdraw_${withdrawalId}`;

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const wallet = await ensureWallet(client);
    if (Number(wallet.balance_cdf) < amount) {
      const err = new Error("Solde trésorerie insuffisant.");
      err.status = 400;
      err.code = "INSUFFICIENT_BALANCE";
      throw err;
    }
    const next = Number(wallet.balance_cdf) - amount;
    await client.query(
      `UPDATE platform_wallet SET balance_cdf = $2, updated_at = NOW() WHERE id = $1`,
      [WALLET_ID, next]
    );
    await client.query(
      `INSERT INTO platform_wallet_withdrawals
         (id, amount_cdf, telecom, destination_phone, status, requested_by, created_at)
       VALUES ($1, $2, $3, $4, 'PENDING', $5, NOW())`,
      [withdrawalId, amount, telecomCode, phone, adminUserId]
    );
    await client.query(
      `INSERT INTO platform_wallet_ledger
         (id, wallet_id, direction, amount_cdf, balance_after_cdf, reason,
          external_reference, created_at)
       VALUES ($1, $2, 'DEBIT', $3, $4, $5, $6, NOW())`,
      [
        crypto.randomUUID(),
        WALLET_ID,
        amount,
        next,
        `Retrait trésorerie ${telecomCode}`,
        reference,
      ]
    );
    await client.query("COMMIT");
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }

  let hubResult;
  try {
    hubResult = await payHub.createPayout({
      amountCdf: amount,
      phone,
      telecom: telecomCode,
      reference,
      idempotencyKey: `safealert:withdraw:${withdrawalId.replace(/-/g, "")}`,
    });
  } catch (err) {
    await refundFailedWithdraw(withdrawalId, amount, "Erreur technique hub");
    throw err;
  }

  if (!hubResult.ok) {
    await refundFailedWithdraw(
      withdrawalId,
      amount,
      hubResult.error || "Refus agrégateur"
    );
    const err = new Error(hubResult.error || "Échec du retrait Mobile Money.");
    err.status = 400;
    throw err;
  }

  await pool.query(
    `UPDATE platform_wallet_withdrawals
     SET external_reference = $2
     WHERE id = $1`,
    [withdrawalId, hubResult.payment_id || hubResult.provider_ref || reference]
  );

  const row = await pool.query(
    `SELECT id, amount_cdf, telecom, destination_phone, status,
            external_reference, failure_reason, requested_by AS requested_by_user_id,
            created_at, completed_at
     FROM platform_wallet_withdrawals WHERE id = $1`,
    [withdrawalId]
  );
  return row.rows[0];
}

async function refundFailedWithdraw(withdrawalId, amount, reason) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const w = await ensureWallet(client);
    const next = Number(w.balance_cdf) + amount;
    await client.query(
      `UPDATE platform_wallet SET balance_cdf = $2, updated_at = NOW() WHERE id = $1`,
      [WALLET_ID, next]
    );
    await client.query(
      `UPDATE platform_wallet_withdrawals
       SET status = 'FAILED', failure_reason = $2, completed_at = NOW()
       WHERE id = $1 AND status = 'PENDING'`,
      [withdrawalId, reason]
    );
    await client.query(
      `INSERT INTO platform_wallet_ledger
         (id, wallet_id, direction, amount_cdf, balance_after_cdf, reason, created_at)
       VALUES ($1, $2, 'CREDIT', $3, $4, $5, NOW())`,
      [
        crypto.randomUUID(),
        WALLET_ID,
        amount,
        next,
        "Annulation retrait échoué",
      ]
    );
    await client.query("COMMIT");
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }
}

async function applyPayoutWebhook({ externalReference, success, failureReason }) {
  if (!externalReference) return;

  const rowRes = await pool.query(
    `SELECT * FROM platform_wallet_withdrawals
     WHERE external_reference = $1 OR id::text = $1
     LIMIT 1`,
    [externalReference]
  );
  const row = rowRes.rows[0];
  if (!row || row.status === "COMPLETED" || row.status === "FAILED") return;

  if (success) {
    await pool.query(
      `UPDATE platform_wallet_withdrawals
       SET status = 'COMPLETED', completed_at = NOW()
       WHERE id = $1`,
      [row.id]
    );
    return;
  }

  await refundFailedWithdraw(
    row.id,
    Number(row.amount_cdf),
    failureReason || "Payout failed"
  );
}

module.exports = {
  WALLET_ID,
  ensureWallet,
  getSnapshot,
  creditFromPaymentIntent,
  listLedger,
  listWithdrawals,
  requestWithdraw,
  applyPayoutWebhook,
};
