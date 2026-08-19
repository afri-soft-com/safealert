import { useState } from "react";
import { Link } from "react-router-dom";
import { API_BASE } from "../api/client";
import { userFacingError } from "../utils/userFacingError";

type PartnerMe = {
  id: string;
  partner_name: string;
  is_active: boolean;
  webhook_url: string | null;
  webhook_events: string;
  rate_limit: number;
};

function partnerPlanLabel(rateLimit: number): string {
  const n = Math.max(1, Number(rateLimit) || 1000);
  if (n <= 500) return "Essai (0 USD)";
  if (n <= 1000) return "Standard (50 USD/mois)";
  if (n <= 5000) return "Pro (100 USD/mois)";
  return "Entreprise (sur devis)";
}

type Delivery = {
  id: string;
  event_type: string;
  status: string;
  response_code: number | null;
  created_at: string;
};

async function partnerRequest<T>(path: string, apiKey: string, options: RequestInit = {}): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      "X-API-Key": apiKey,
      ...(options.headers as Record<string, string>),
    },
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    const msg = typeof body.error === "string" ? body.error : "Erreur";
    throw new Error(msg);
  }
  return body as T;
}

export default function PartnerPortalPage() {
  const [apiKey, setApiKey] = useState(localStorage.getItem("safealert_partner_key") || "");
  const [me, setMe] = useState<PartnerMe | null>(null);
  const [deliveries, setDeliveries] = useState<Delivery[]>([]);
  const [webhookUrl, setWebhookUrl] = useState("");
  const [error, setError] = useState("");
  const [msg, setMsg] = useState("");

  const connect = async () => {
    setError("");
    setMsg("");
    if (!apiKey.trim()) {
      setError("Saisissez votre clé API partenaire.");
      return;
    }
    try {
      localStorage.setItem("safealert_partner_key", apiKey.trim());
      const profile = await partnerRequest<PartnerMe>("/partner/me", apiKey.trim());
      setMe(profile);
      setWebhookUrl(profile.webhook_url || "");
      const d = await partnerRequest<Delivery[] | { data?: Delivery[] }>(
        "/partner/webhook/deliveries",
        apiKey.trim()
      );
      setDeliveries(Array.isArray(d) ? d : d.data || []);
    } catch (e) {
      setError(userFacingError(e, "Clé API invalide ou expirée."));
      setMe(null);
    }
  };

  const saveWebhook = async () => {
    if (!apiKey.trim()) return;
    try {
      await partnerRequest("/partner/webhook", apiKey.trim(), {
        method: "PUT",
        body: JSON.stringify({ webhook_url: webhookUrl, webhook_events: "sos,incident,cancel" }),
      });
      setMsg("Adresse de notification enregistrée.");
      await connect();
    } catch (e) {
      setError(userFacingError(e, "Enregistrement impossible. Réessayez."));
    }
  };

  return (
    <div className="login-page" style={{ alignItems: "flex-start", paddingTop: 48 }}>
      <div style={{ width: "100%", maxWidth: 720, margin: "0 auto", padding: 16 }}>
        <header className="page-header">
          <h2>Portail partenaire SafeAlert</h2>
          <p>Configurez vos notifications d&apos;alertes avec votre clé API</p>
        </header>

        <div className="form-card" style={{ maxWidth: 520 }}>
          <label htmlFor="partner-key">Clé API</label>
          <input
            id="partner-key"
            type="password"
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            placeholder="Clé fournie par l'administrateur"
          />
          <button type="button" className="btn btn-primary" onClick={connect} style={{ marginTop: 12 }}>
            Se connecter
          </button>
        </div>

        {error && <div className="form-error">{error}</div>}
        {msg && <div className="form-success">{msg}</div>}

        {me && (
          <>
            <div className="stats-grid" style={{ marginTop: 20 }}>
              <div className="stat-card">
                <div className="label">Partenaire</div>
                <div className="value" style={{ fontSize: 18 }}>
                  {me.partner_name}
                </div>
              </div>
              <div className="stat-card">
                <div className="label">Statut</div>
                <div className="value" style={{ fontSize: 18 }}>
                  {me.is_active ? "Actif" : "Inactif"}
                </div>
              </div>
              <div className="stat-card">
                <div className="label">Plan</div>
                <div className="value" style={{ fontSize: 16 }}>
                  {partnerPlanLabel(me.rate_limit)}
                </div>
              </div>
              <div className="stat-card">
                <div className="label">Limite (15 min)</div>
                <div className="value" style={{ fontSize: 18 }}>
                  {me.rate_limit}
                </div>
              </div>
            </div>

            <div className="form-card" style={{ marginTop: 20, maxWidth: 520 }}>
              <label htmlFor="webhook">Adresse de notification (URL)</label>
              <input
                id="webhook"
                type="url"
                value={webhookUrl}
                onChange={(e) => setWebhookUrl(e.target.value)}
                placeholder="https://votre-serveur.exemple/webhook"
              />
              <button type="button" className="btn btn-primary" onClick={saveWebhook} style={{ marginTop: 12 }}>
                Enregistrer
              </button>
            </div>

            <h3 style={{ marginTop: 24 }}>Dernières livraisons</h3>
            {deliveries.length === 0 ? (
              <p className="empty">Aucune livraison pour le moment.</p>
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Événement</th>
                      <th>Statut</th>
                      <th>Code</th>
                      <th>Date</th>
                    </tr>
                  </thead>
                  <tbody>
                    {deliveries.map((d) => (
                      <tr key={d.id}>
                        <td>{d.event_type}</td>
                        <td>{d.status}</td>
                        <td>{d.response_code ?? "—"}</td>
                        <td>{new Date(d.created_at).toLocaleString("fr-FR")}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </>
        )}

        <p className="form-hint" style={{ marginTop: 24 }}>
          Administrateur plateforme ? <Link to="/connexion">Connexion console admin</Link>
        </p>
      </div>
    </div>
  );
}
