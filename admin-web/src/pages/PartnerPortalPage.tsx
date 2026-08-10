import { useState } from "react";
import { API_BASE } from "../api/client";

type PartnerMe = {
  id: string;
  partner_name: string;
  is_active: boolean;
  webhook_url: string | null;
  webhook_events: string;
  rate_limit: number;
};

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
  if (!res.ok) throw new Error(body.error || "Erreur");
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
    try {
      localStorage.setItem("safealert_partner_key", apiKey);
      const profile = await partnerRequest<PartnerMe>("/partner/me", apiKey);
      setMe(profile);
      setWebhookUrl(profile.webhook_url || "");
      const d = await partnerRequest<Delivery[]>("/partner/webhook/deliveries", apiKey);
      setDeliveries(Array.isArray(d) ? d : (d as { data?: Delivery[] }).data || []);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Connexion impossible");
      setMe(null);
    }
  };

  const saveWebhook = async () => {
    if (!apiKey) return;
    try {
      await partnerRequest("/partner/webhook", apiKey, {
        method: "PUT",
        body: JSON.stringify({ webhook_url: webhookUrl, webhook_events: "sos,incident,cancel" }),
      });
      setMsg("Webhook enregistré");
      await connect();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Erreur");
    }
  };

  return (
    <>
      <header className="page-header">
        <h2>Portail partenaire</h2>
        <p>Configurez vos webhooks SOS / incidents avec votre clé API</p>
      </header>

      <div className="form-card" style={{ maxWidth: 520 }}>
        <label>Clé API (X-API-Key)</label>
        <input
          type="password"
          value={apiKey}
          onChange={(e) => setApiKey(e.target.value)}
          placeholder="Clé partenaire"
        />
        <button type="button" onClick={connect} style={{ marginTop: 12 }}>
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
              <div className="value" style={{ fontSize: 18 }}>{me.partner_name}</div>
            </div>
            <div className="stat-card">
              <div className="label">Statut</div>
              <div className="value" style={{ fontSize: 18 }}>{me.is_active ? "Actif" : "Inactif"}</div>
            </div>
          </div>

          <h3 style={{ marginTop: 24 }}>Webhook</h3>
          <p style={{ fontSize: 13 }}>
            Événements : <code>sos</code>, <code>incident</code>, <code>cancel</code>.
            Signature HMAC-SHA256 dans <code>X-SafeAlert-Signature</code>.
          </p>
          <input
            type="url"
            value={webhookUrl}
            onChange={(e) => setWebhookUrl(e.target.value)}
            placeholder="https://votre-serveur/webhooks/safealert"
            style={{ width: "100%", maxWidth: 520 }}
          />
          <button type="button" onClick={saveWebhook} style={{ marginTop: 8 }}>
            Enregistrer le webhook
          </button>

          <h3 style={{ marginTop: 24 }}>Dernières livraisons</h3>
          <table>
            <thead>
              <tr>
                <th>Événement</th>
                <th>Statut</th>
                <th>HTTP</th>
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
              {deliveries.length === 0 && (
                <tr><td colSpan={4}>Aucune livraison</td></tr>
              )}
            </tbody>
          </table>
        </>
      )}
    </>
  );
}
