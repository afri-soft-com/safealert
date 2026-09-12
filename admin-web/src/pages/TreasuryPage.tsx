import { useCallback, useEffect, useState } from "react";
import { api } from "../api/client";
import { userFacingError } from "../utils/userFacingError";

function fmtCdf(n: number): string {
  return `${Number(n || 0).toLocaleString("fr-FR")} FC`;
}

function fmtWhen(iso?: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleString("fr-FR");
}

export default function TreasuryPage() {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [balance, setBalance] = useState(0);
  const [updatedAt, setUpdatedAt] = useState<string | null>(null);
  const [hubOk, setHubOk] = useState(false);
  const [minWithdraw, setMinWithdraw] = useState(2300);
  const [ledger, setLedger] = useState<
    Array<{
      id: string;
      direction: string;
      amount_cdf: number;
      balance_after_cdf: number;
      reason?: string | null;
      created_at: string;
    }>
  >([]);
  const [withdrawals, setWithdrawals] = useState<
    Array<{
      id: string;
      amount_cdf: number;
      telecom: string;
      destination_phone: string;
      status: string;
      failure_reason?: string | null;
      created_at: string;
      completed_at?: string | null;
    }>
  >([]);

  const [amount, setAmount] = useState("");
  const [phone, setPhone] = useState("");
  const [telecom, setTelecom] = useState("MP");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await api.getTreasury();
      setBalance(res.balance_cdf);
      setUpdatedAt(res.updated_at);
      setHubOk(res.pay_hub_configured);
      setMinWithdraw(res.min_withdraw_cdf || 2300);
      setLedger(res.ledger || []);
      setWithdrawals(res.withdrawals || []);
    } catch (err) {
      setError(userFacingError(err, "Impossible de charger la trésorerie."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const handleWithdraw = async (e: React.FormEvent) => {
    e.preventDefault();
    setMessage("");
    const amountCdf = Math.round(Number(amount));
    if (!Number.isFinite(amountCdf) || amountCdf < minWithdraw) {
      setMessage(`Montant minimum : ${fmtCdf(minWithdraw)}`);
      return;
    }
    if (!phone.trim()) {
      setMessage("Numéro de destination requis.");
      return;
    }
    setBusy(true);
    try {
      const res = await api.withdrawTreasury({
        amount_cdf: amountCdf,
        telecom,
        phone: phone.trim(),
      });
      setMessage(res.message || "Retrait initié.");
      setAmount("");
      await load();
    } catch (err) {
      setMessage(userFacingError(err, "Retrait impossible."));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="page">
      <header className="page-header">
        <h2>Trésorerie</h2>
        <p>Solde plateforme (encaissements Premium Mobile Money) et retraits B2C.</p>
      </header>

      {error ? <p className="error-banner">{error}</p> : null}
      {loading ? <p>Chargement…</p> : null}

      {!loading && (
        <>
          <section className="card-grid" style={{ marginBottom: 24 }}>
            <div className="stat-card">
              <div className="stat-label">Solde</div>
              <div className="stat-value">{fmtCdf(balance)}</div>
              <div className="muted">Maj {fmtWhen(updatedAt)}</div>
            </div>
            <div className="stat-card">
              <div className="stat-label">Hub AfriSoft</div>
              <div className="stat-value">{hubOk ? "OK" : "Non configuré"}</div>
              <div className="muted">Préférer MP / AM pour les retraits</div>
            </div>
          </section>

          <section style={{ marginBottom: 32 }}>
            <h3>Retrait Mobile Money</h3>
            <form onSubmit={handleWithdraw} className="form-row" style={{ gap: 12, flexWrap: "wrap" }}>
              <input
                type="number"
                min={minWithdraw}
                step={100}
                placeholder={`Montant CDF (≥ ${minWithdraw})`}
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                disabled={busy || !hubOk}
              />
              <select
                value={telecom}
                onChange={(e) => setTelecom(e.target.value)}
                disabled={busy || !hubOk}
              >
                <option value="MP">M-Pesa (recommandé)</option>
                <option value="AM">Airtel Money (recommandé)</option>
                <option value="OM">Orange Money</option>
              </select>
              <input
                type="tel"
                placeholder="Téléphone destinataire (+243…)"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                disabled={busy || !hubOk}
              />
              <button type="submit" disabled={busy || !hubOk}>
                {busy ? "Envoi…" : "Retirer"}
              </button>
            </form>
            {message ? <p className="muted" style={{ marginTop: 8 }}>{message}</p> : null}
          </section>

          <section style={{ marginBottom: 32 }}>
            <h3>Derniers mouvements</h3>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Sens</th>
                  <th>Montant</th>
                  <th>Solde après</th>
                  <th>Motif</th>
                </tr>
              </thead>
              <tbody>
                {ledger.length === 0 ? (
                  <tr>
                    <td colSpan={5}>Aucun mouvement</td>
                  </tr>
                ) : (
                  ledger.map((row) => (
                    <tr key={row.id}>
                      <td>{fmtWhen(row.created_at)}</td>
                      <td>{row.direction}</td>
                      <td>{fmtCdf(row.amount_cdf)}</td>
                      <td>{fmtCdf(row.balance_after_cdf)}</td>
                      <td>{row.reason || "—"}</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </section>

          <section>
            <h3>Retraits</h3>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Montant</th>
                  <th>Opérateur</th>
                  <th>Destination</th>
                  <th>Statut</th>
                </tr>
              </thead>
              <tbody>
                {withdrawals.length === 0 ? (
                  <tr>
                    <td colSpan={5}>Aucun retrait</td>
                  </tr>
                ) : (
                  withdrawals.map((row) => (
                    <tr key={row.id}>
                      <td>{fmtWhen(row.created_at)}</td>
                      <td>{fmtCdf(row.amount_cdf)}</td>
                      <td>{row.telecom}</td>
                      <td>{row.destination_phone}</td>
                      <td>
                        {row.status}
                        {row.failure_reason ? ` — ${row.failure_reason}` : ""}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </section>
        </>
      )}
    </div>
  );
}
