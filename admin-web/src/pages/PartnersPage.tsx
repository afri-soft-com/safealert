import { FormEvent, useEffect, useState } from "react";
import { api, type PartnerRow } from "../api/client";
import { userFacingError } from "../utils/userFacingError";

export default function PartnersPage() {
  const [partners, setPartners] = useState<PartnerRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [name, setName] = useState("");
  const [newKey, setNewKey] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState("");

  const load = async () => {
    setLoading(true);
    setError("");
    try {
      const res = await api.getPartners();
      setPartners(res.data);
    } catch (err) {
      setError(userFacingError(err, "Impossible de charger les partenaires."));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load();
  }, []);

  const handleCreate = async (e: FormEvent) => {
    e.preventDefault();
    if (!name.trim() || creating) return;
    setCreating(true);
    setError("");
    try {
      const res = await api.createPartner(name.trim());
      setNewKey(res.api_key);
      setName("");
      await load();
    } catch (err) {
      setError(userFacingError(err, "Impossible de créer le partenaire."));
    } finally {
      setCreating(false);
    }
  };

  const handleRevoke = async (id: string, partnerName: string) => {
    if (!confirm(`Révoquer la clé de « ${partnerName} » ?`)) return;
    setError("");
    try {
      await api.revokePartner(id);
      await load();
    } catch (err) {
      setError(userFacingError(err, "Impossible de révoquer la clé."));
    }
  };

  const maskKey = (key: string) => `${key.slice(0, 8)}…${key.slice(-4)}`;

  return (
    <>
      <header className="page-header">
        <h2>Partenaires API</h2>
        <p>Clés d'accès pour les organisations partenaires (ONG, etc.)</p>
      </header>

      {error && <div className="form-error">{error}</div>}

      <div className="card" style={{ marginBottom: "1.5rem" }}>
        <div className="card-toolbar">
          <form onSubmit={handleCreate} style={{ display: "flex", gap: "0.75rem", flex: 1 }}>
            <input
              type="text"
              placeholder="Nom de l'organisation"
              value={name}
              onChange={(e) => setName(e.target.value)}
              style={{ flex: 1 }}
              required
            />
            <button type="submit" className="btn btn-primary" disabled={creating}>
              {creating ? "Création…" : "Créer une clé"}
            </button>
          </form>
        </div>
      </div>

      {newKey && (
        <div className="modal-overlay" onClick={() => setNewKey(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>Clé API créée</h3>
            <p>Conservez cette clé — elle ne sera plus affichée en entier :</p>
            <div className="api-key-display">{newKey}</div>
            <div className="modal-actions">
              <button type="button" className="btn btn-primary" onClick={() => setNewKey(null)}>
                J'ai copié la clé
              </button>
            </div>
          </div>
        </div>
      )}

      <div className="card">
        {loading ? (
          <div className="loading">Chargement…</div>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Organisation</th>
                  <th>Clé API</th>
                  <th>Statut</th>
                  <th>Limite / h</th>
                  <th>Créée le</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {partners.length === 0 ? (
                  <tr>
                    <td colSpan={6} className="empty">
                      Aucun partenaire
                    </td>
                  </tr>
                ) : (
                  partners.map((p) => (
                    <tr key={p.id}>
                      <td>{p.partner_name}</td>
                      <td>
                        <code>{maskKey(p.api_key)}</code>
                      </td>
                      <td>
                        <span className={`badge ${p.is_active ? "badge-active" : "badge-inactive"}`}>
                          {p.is_active ? "Active" : "Révoquée"}
                        </span>
                      </td>
                      <td>{p.rate_limit}</td>
                      <td>{new Date(p.created_at).toLocaleDateString("fr-FR")}</td>
                      <td>
                        {p.is_active && (
                          <button
                            type="button"
                            className="btn btn-danger"
                            onClick={() => handleRevoke(p.id, p.partner_name)}
                          >
                            Révoquer
                          </button>
                        )}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  );
}
