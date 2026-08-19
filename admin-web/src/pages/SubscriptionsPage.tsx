import { useCallback, useEffect, useState } from "react";
import { api, type UserRow } from "../api/client";
import { userFacingError } from "../utils/userFacingError";

function untilLabel(until?: string | null): string {
  if (!until) return "—";
  const d = new Date(until);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleDateString("fr-FR");
}

export default function SubscriptionsPage() {
  const [rows, setRows] = useState<UserRow[]>([]);
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<"all" | "active" | "expired">("all");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [busyId, setBusyId] = useState<string | null>(null);
  const [featureEnabled, setFeatureEnabled] = useState(true);
  const [stats, setStats] = useState({
    active: 0,
    expired: 0,
    expiring_7d: 0,
    estimated_mrr_usd: 0,
  });
  const [pricing, setPricing] = useState({
    monthly_usd: 2,
    yearly_usd: 20,
    monthly_cdf_approx: 5500,
    yearly_cdf_approx: 55000,
  });
  const [grantPhone, setGrantPhone] = useState("");
  const [grantDays, setGrantDays] = useState("30");

  const limit = 20;

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await api.getPremiumSubscriptions(page, limit, query, status);
      setRows(res.data);
      setTotal(res.total);
      setFeatureEnabled(res.feature_enabled);
      setStats(res.stats);
      setPricing({
        monthly_usd: res.pricing.monthly_usd,
        yearly_usd: res.pricing.yearly_usd,
        monthly_cdf_approx: res.pricing.monthly_cdf_approx,
        yearly_cdf_approx: res.pricing.yearly_cdf_approx,
      });
    } catch (err) {
      setError(userFacingError(err, "Impossible de charger les abonnements."));
      setRows([]);
      setTotal(0);
    } finally {
      setLoading(false);
    }
  }, [page, query, status]);

  useEffect(() => {
    load();
  }, [load]);

  useEffect(() => {
    const t = setTimeout(() => {
      setPage(1);
      setQuery(search.trim());
    }, 350);
    return () => clearTimeout(t);
  }, [search]);

  const handleGrant = async (id: string, daysHint = "30") => {
    const raw = window.prompt("Nombre de jours Premium à accorder ?", daysHint);
    if (raw == null) return;
    const days = Math.min(365, Math.max(1, parseInt(raw, 10) || 30));
    setBusyId(id);
    try {
      await api.grantPremium(id, days);
      await load();
    } catch (err) {
      alert(userFacingError(err, "Impossible d'accorder Premium."));
    } finally {
      setBusyId(null);
    }
  };

  const handleGrantBySearch = async () => {
    const q = grantPhone.trim();
    if (!q) {
      alert("Saisissez un téléphone ou un pseudo.");
      return;
    }
    const days = Math.min(365, Math.max(1, parseInt(grantDays, 10) || 30));
    setBusyId("search");
    try {
      const found = await api.getUsers(1, 5, q);
      if (!found.data.length) {
        alert("Aucun utilisateur trouvé.");
        return;
      }
      const user = found.data[0];
      if (found.data.length > 1 && !window.confirm(`Accorder Premium à ${user.pseudo} (${user.phone}) ?`)) {
        return;
      }
      await api.grantPremium(user.id, days);
      setGrantPhone("");
      await load();
    } catch (err) {
      alert(userFacingError(err, "Impossible d'accorder Premium."));
    } finally {
      setBusyId(null);
    }
  };

  const handleRevoke = async (id: string) => {
    if (!window.confirm("Révoquer Premium pour cet utilisateur ?")) return;
    setBusyId(id);
    try {
      await api.revokePremium(id);
      await load();
    } catch (err) {
      alert(userFacingError(err, "Impossible de révoquer Premium."));
    } finally {
      setBusyId(null);
    }
  };

  const totalPages = Math.max(1, Math.ceil(total / limit));

  return (
    <>
      <header className="page-header">
        <h2>Abonnements Premium</h2>
        <p>Gestion économique B2C — accorder, prolonger ou révoquer Premium</p>
      </header>

      {!featureEnabled && (
        <div className="form-error" style={{ marginBottom: 16 }}>
          Le flag <code>FEATURE_PREMIUM</code> est désactivé : les limites Free/Premium
          ne s&apos;appliquent pas encore dans l&apos;app, mais vous pouvez déjà attribuer
          des dates <code>premium_until</code>.
        </div>
      )}

      {error && <div className="form-error">{error}</div>}

      <div className="stats-grid">
        <div className="stat-card accent">
          <div className="label">Actifs</div>
          <div className="value">{stats.active}</div>
        </div>
        <div className="stat-card">
          <div className="label">Expirent sous 7 j</div>
          <div className="value">{stats.expiring_7d}</div>
        </div>
        <div className="stat-card">
          <div className="label">Expirés</div>
          <div className="value">{stats.expired}</div>
        </div>
        <div className="stat-card accent">
          <div className="label">MRR estimé</div>
          <div className="value">{stats.estimated_mrr_usd} USD</div>
        </div>
      </div>

      <div className="card" style={{ marginTop: 16 }}>
        <h3>Offre citoyenne</h3>
        <p style={{ color: "var(--muted, #666)", fontSize: 14 }}>
          Gratuit : 5 contacts, 3 trajets / semaine, ETA 2 h, historique 30.
          Premium : illimité, ETA 12 h, 25 contacts, historique 100, priorité SOS.
        </p>
        <table>
          <thead>
            <tr>
              <th>Plan</th>
              <th>Prix</th>
              <th>Équivalent CDF</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>Mensuel</td>
              <td>{pricing.monthly_usd} USD</td>
              <td>~{pricing.monthly_cdf_approx.toLocaleString("fr-FR")} CDF</td>
            </tr>
            <tr>
              <td>Annuel</td>
              <td>{pricing.yearly_usd} USD</td>
              <td>~{pricing.yearly_cdf_approx.toLocaleString("fr-FR")} CDF</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div className="card" style={{ marginTop: 16 }}>
        <h3>Accorder un abonnement</h3>
        <div className="card-toolbar" style={{ flexWrap: "wrap", gap: 8 }}>
          <input
            type="search"
            placeholder="Téléphone ou pseudo…"
            value={grantPhone}
            onChange={(e) => setGrantPhone(e.target.value)}
            style={{ flex: 1, minWidth: 180 }}
          />
          <input
            type="number"
            min={1}
            max={365}
            value={grantDays}
            onChange={(e) => setGrantDays(e.target.value)}
            style={{ width: 90 }}
            title="Jours"
          />
          <button
            type="button"
            className="btn"
            disabled={busyId === "search"}
            onClick={handleGrantBySearch}
          >
            Accorder
          </button>
        </div>
      </div>

      <div className="card" style={{ marginTop: 16 }}>
        <div className="card-toolbar">
          <input
            type="search"
            placeholder="Filtrer les abonnés…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={{ flex: 1, minWidth: 180 }}
          />
          <select
            value={status}
            onChange={(e) => {
              setPage(1);
              setStatus(e.target.value as "all" | "active" | "expired");
            }}
          >
            <option value="all">Tous</option>
            <option value="active">Actifs</option>
            <option value="expired">Expirés</option>
          </select>
        </div>

        {loading ? (
          <div className="loading">Chargement…</div>
        ) : (
          <>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Pseudo</th>
                    <th>Téléphone</th>
                    <th>Rôle</th>
                    <th>Expire le</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="empty">
                        Aucun abonnement
                      </td>
                    </tr>
                  ) : (
                    rows.map((u) => {
                      const active =
                        u.premium_until &&
                        new Date(u.premium_until).getTime() > Date.now();
                      return (
                        <tr key={u.id}>
                          <td>{u.pseudo}</td>
                          <td>{u.phone}</td>
                          <td>{u.role}</td>
                          <td>
                            {active ? (
                              <strong>{untilLabel(u.premium_until)}</strong>
                            ) : (
                              untilLabel(u.premium_until)
                            )}
                          </td>
                          <td>
                            <button
                              type="button"
                              className="btn btn-secondary"
                              style={{ padding: "0.25rem 0.45rem", marginRight: 4 }}
                              disabled={busyId === u.id}
                              onClick={() => handleGrant(u.id, "30")}
                            >
                              Prolonger
                            </button>
                            <button
                              type="button"
                              className="btn btn-secondary"
                              style={{ padding: "0.25rem 0.45rem" }}
                              disabled={busyId === u.id}
                              onClick={() => handleRevoke(u.id)}
                            >
                              Révoquer
                            </button>
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>
            <div className="pagination">
              <span>
                {total} abonnement{total !== 1 ? "s" : ""} — page {page}/{totalPages}
              </span>
              <div className="pagination-btns">
                <button
                  type="button"
                  className="btn btn-secondary"
                  disabled={page <= 1}
                  onClick={() => setPage((p) => p - 1)}
                >
                  Précédent
                </button>
                <button
                  type="button"
                  className="btn btn-secondary"
                  disabled={page >= totalPages}
                  onClick={() => setPage((p) => p + 1)}
                >
                  Suivant
                </button>
              </div>
            </div>
          </>
        )}
      </div>
    </>
  );
}
