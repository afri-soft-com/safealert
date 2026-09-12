const platformWallet = require("../services/platformWallet");
const payHub = require("../services/afrisoftPayHub");
const { fail } = require("../utils/httpError");

/** GET /api/admin/treasury */
const getTreasury = async (req, res) => {
  try {
    const [snap, ledger, withdrawals] = await Promise.all([
      platformWallet.getSnapshot(),
      platformWallet.listLedger(40),
      platformWallet.listWithdrawals(40),
    ]);
    return res.json({
      balance_cdf: snap.balance_cdf,
      updated_at: snap.updated_at,
      pay_hub_configured: payHub.isConfigured(),
      preferred_telecoms: ["MP", "AM"],
      min_withdraw_cdf: payHub.MIN_CDF,
      ledger,
      withdrawals,
    });
  } catch (err) {
    return fail(res, err, "Impossible de charger la trésorerie.");
  }
};

/** POST /api/admin/treasury/withdraw — platform_admin only (enforced in route) */
const withdrawTreasury = async (req, res) => {
  const amount = req.body.amount_cdf ?? req.body.amount;
  const telecom = req.body.telecom || req.body.operator || "MP";
  const phone = req.body.phone || req.body.destination_phone;

  if (!phone) {
    return res.status(400).json({ error: "Numéro de destination requis." });
  }
  if (amount == null) {
    return res.status(400).json({ error: "Montant requis (amount_cdf)." });
  }

  try {
    const row = await platformWallet.requestWithdraw({
      adminUserId: req.userId,
      amountCdf: amount,
      telecom,
      destinationPhone: phone,
    });
    return res.status(201).json({
      message: "Retrait initié — confirmez sur le téléphone destinataire si demandé.",
      withdrawal: row,
    });
  } catch (err) {
    if (err.status) {
      return res.status(err.status).json({ error: err.message, code: err.code });
    }
    return fail(res, err, "Impossible d'initier le retrait.");
  }
};

module.exports = { getTreasury, withdrawTreasury };
