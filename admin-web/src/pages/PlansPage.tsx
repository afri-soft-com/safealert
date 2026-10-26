import { FormEvent, useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import {
  api,
  isSuperAdmin,
  type PremiumEntitlements,
  type PremiumPlansPayload,
} from "../api/client";
import { useAuth } from "../context/AuthContext";
import { userFacingError } from "../utils/userFacingError";

type EntKey = keyof PremiumEntitlements;

const ENT_FIELDS: Array<{
  key: EntKey;
  label: string;
  type: "number" | "bool" | "nullable-number";
  hint?: string;
}> = [
  { key: "contacts_max", label: "Contacts max", type: "number" },
  {
    key: "trips_per_week",
    label: "Trajets / semaine",
    type: "nullable-number",
    hint: "Laisser vide = illimité",
  },
  { key: "trip_eta_max_minutes", label: "ETA max (min)", type: "number" },
  { key: "history_limit", label: "Historique (entrées)", type: "number" },
  { key: "live_circles_max", label: "Cercles live max", type: "number" },
  { key: "sos_priority", label: "SOS prioritaire", type: "bool" },
  { key: "sos_mediation", label: "Médiation SOS", type: "bool" },
];

function emptyEnt(): PremiumEntitlements {
  return {
    contacts_max: 5,
    trips_per_week: 3,
    trip_eta_max_minutes: 120,
    history_limit: 30,
    sos_priority: false,
    sos_mediation: false,
    live_circles_max: 1,
  };
}

function EntForm({
  title,
  value,
  onChange,
  disabled,
}: {
  title: string;
  value: PremiumEntitlements;
  onChange: (next: PremiumEntitlements) => void;
  disabled?: boolean;
}) {
  return (
    <div className="card" style={{ flex: 1, minWidth: 280 }}>
      <h3>{title}</h3>
      <div style={{ display: "grid", gap: 10 }}>
        {ENT_FIELDS.map((f) => {
          if (f.type === "bool") {
            return (
              <label
                key={f.key}
                style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 14 }}
              >
                <input
                  type="checkbox"
                  checked={Boolean(value[f.key])}
                  disabled={disabled}
                  onChange={(e) => onChange({ ...value, [f.key]: e.target.checked })}
                />
                {f.label}
              </label>
            );
          }
          const raw =
            f.type === "nullable-number" && value[f.key] == null
              ? ""
              : String(value[f.key] ?? "");
          return (
            <label key={f.key} style={{ display: "grid", gap: 4, fontSize: 13 }}>
              <span>
                {f.label}
                {f.hint ? (
                  <span style={{ color: "var(--muted, #666)", fontWeight: 400 }}>
                    {" "}
                    — {f.hint}
                  </span>
                ) : null}
              </span>
              <input
                type="number"
                min={0}
                value={raw}
                disabled={disabled}
                placeholder={f.type === "nullable-number" ? "Illimité" : undefined}
                onChange={(e) => {
                  const t = e.target.value.trim();
                  if (f.type === "nullable-number" && t === "") {
                    onChange({ ...value, [f.key]: null });
                    return;
                  }
                  const n = parseInt(t, 10);
                  onChange({
                    ...value,
                    [f.key]: Number.isFinite(n) ? n : value[f.key],
                  });
                }}
              />
            </label>
          );
        })}
      </div>
    </div>
  );
}

export default function PlansPage() {
  const { user } = useAuth();
  const canWrite = isSuperAdmin(user?.role);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [free, setFree] = useState<PremiumEntitlements>(emptyEnt());
  const [premium, setPremium] = useState<PremiumEntitlements>(emptyEnt());
  const [monthlyUsd, setMonthlyUsd] = useState("2");
  const [yearlyUsd, setYearlyUsd] = useState("20");
  const [cdfHint, setCdfHint] = useState({ monthly: 0, yearly: 0, rate: 2850 });
  const [defaults, setDefaults] = useState<PremiumPlansPayload["defaults"] | null>(null);

  const applyPayload = (payload: PremiumPlansPayload) => {
    setFree(payload.free);
    setPremium(payload.premium);
    setMonthlyUsd(String(payload.pricing.monthly_usd));
    setYearlyUsd(String(payload.pricing.yearly_usd));
    setCdfHint({
      monthly: payload.pricing.monthly_cdf_approx || payload.pricing.monthly_cdf || 0,
      yearly: payload.pricing.yearly_cdf_approx || payload.pricing.yearly_cdf || 0,
      rate: payload.pricing.usd_to_cdf_rate || 2850,
    });
    setDefaults(payload.defaults);
  };

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const payload = await api.getPremiumPlans();
      applyPayload(payload);
    } catch (err) {
      setError(userFacingError(err, "Impossible de charger les offres."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const save = async (e: FormEvent) => {
    e.preventDefault();
    if (!canWrite || saving) return;
    setSaving(true);
    setError("");
    setSuccess("");
    try {
      const payload = await api.savePremiumPlans({
        free,
        premium,
        pricing: {
          currency: "USD",
          monthly_usd: Number(monthlyUsd) || 0,
          yearly_usd: Number(yearlyUsd) || 0,
        },
      });
      applyPayload(payload);
      setSuccess("Offres Gratuit et Premium enregistrées. Appliquées immédiatement côté API.");
    } catch (err) {
      setError(userFacingError(err, "Impossible d'enregistrer les offres."));
    } finally {
      setSaving(false);
    }
  };

  const resetDefaults = async () => {
    if (!canWrite) return;
    if (
      !window.confirm(
        "Réinitialiser Gratuit, Premium et les prix aux valeurs d'usine SafeAlert ?"
      )
    ) {
      return;
    }
    setSaving(true);
    setError("");
    setSuccess("");
    try {
      const payload = await api.resetPremiumPlans();
      applyPayload(payload);
      setSuccess("Offres réinitialisées aux valeurs par défaut.");
    } catch (err) {
      setError(userFacingError(err, "Impossible de réinitialiser."));
    } finally {
      setSaving(false);
    }
  };

  if (!canWrite) {
    return (
      <>
        <header className="page-header">
          <h2>Offres Gratuit / Premium</h2>
          <p>Réservé au super administrateur.</p>
        </header>
        <div className="card">
          <p>
            Vous pouvez consulter les abonnements sur{" "}
            <Link to="/abonnements">Abonnements</Link>, mais seule la plateforme admin peut
            modifier les plafonds et les prix.
          </p>
        </div>
      </>
    );
  }

  return (
    <>
      <header className="page-header">
        <h2>Offres Gratuit / Premium</h2>
        <p>Définir les plafonds du plan gratuit, du Premium et les tarifs Mobile Money</p>
      </header>

      {error && <div className="form-error">{error}</div>}
      {success && (
        <div
          className="card"
          style={{
            marginBottom: 12,
            background: "rgba(11,110,110,0.08)",
            borderColor: "#0b6e6e",
          }}
        >
          {success}
        </div>
      )}

      {loading ? (
        <div className="loading">Chargement…</div>
      ) : (
        <form onSubmit={save}>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 16, marginBottom: 16 }}>
            <EntForm title="Plan Gratuit" value={free} onChange={setFree} disabled={saving} />
            <EntForm
              title="Plan Premium"
              value={premium}
              onChange={setPremium}
              disabled={saving}
            />
          </div>

          <div className="card" style={{ marginBottom: 16 }}>
            <h3>Tarification Premium</h3>
            <p style={{ fontSize: 13, color: "var(--muted, #666)" }}>
              Les montants CDF sont recalculés avec le taux USD→CDF serveur (≈ {cdfHint.rate}).
            </p>
            <div
              style={{
                display: "grid",
                gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
                gap: 12,
              }}
            >
              <label style={{ display: "grid", gap: 4, fontSize: 13 }}>
                Mensuel (USD)
                <input
                  type="number"
                  min={0}
                  step="0.01"
                  value={monthlyUsd}
                  disabled={saving}
                  onChange={(e) => setMonthlyUsd(e.target.value)}
                />
                <span style={{ color: "var(--muted, #666)" }}>
                  ≈ {cdfHint.monthly.toLocaleString("fr-FR")} CDF (dernier calcul)
                </span>
              </label>
              <label style={{ display: "grid", gap: 4, fontSize: 13 }}>
                Annuel (USD)
                <input
                  type="number"
                  min={0}
                  step="0.01"
                  value={yearlyUsd}
                  disabled={saving}
                  onChange={(e) => setYearlyUsd(e.target.value)}
                />
                <span style={{ color: "var(--muted, #666)" }}>
                  ≈ {cdfHint.yearly.toLocaleString("fr-FR")} CDF (dernier calcul)
                </span>
              </label>
            </div>
          </div>

          <div className="card-toolbar" style={{ gap: 8, flexWrap: "wrap" }}>
            <button type="submit" className="btn" disabled={saving}>
              {saving ? "Enregistrement…" : "Enregistrer"}
            </button>
            <button
              type="button"
              className="btn btn-secondary"
              disabled={saving}
              onClick={resetDefaults}
            >
              Réinitialiser (défauts)
            </button>
            <Link to="/abonnements" className="btn btn-secondary">
              Voir les abonnés
            </Link>
            {defaults && (
              <span style={{ fontSize: 12, color: "var(--muted, #666)" }}>
                Défaut usine : gratuit {defaults.free.contacts_max} contacts /{" "}
                {defaults.free.trips_per_week ?? "∞"} trajets — Premium{" "}
                {defaults.pricing.monthly_usd}$ / mois
              </span>
            )}
          </div>
        </form>
      )}
    </>
  );
}
