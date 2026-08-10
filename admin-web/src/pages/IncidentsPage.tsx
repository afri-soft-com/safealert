import { useCallback, useEffect, useState } from "react";
import {
  api,
  INCIDENT_STATUS_LABELS,
  INCIDENT_TYPE_LABELS,
  SEVERITY_LABELS,
  type IncidentRow,
} from "../api/client";
import { userFacingError } from "../utils/userFacingError";

export default function IncidentsPage() {
  const [incidents, setIncidents] = useState<IncidentRow[]>([]);
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [status, setStatus] = useState("");
  const [zone, setZone] = useState("");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [selected, setSelected] = useState<IncidentRow | null>(null);

  const limit = 20;

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const params: Record<string, string> = {
        page: String(page),
        limit: String(limit),
      };
      if (status) params.status = status;
      if (zone) params.zone = zone;
      if (from) params.from = from;
      if (to) params.to = to;

      const res = await api.getIncidents(params);
      setIncidents(res.data);
      setTotal(res.total);
    } catch (err) {
      setError(userFacingError(err, "Impossible de charger les incidents."));
      setIncidents([]);
      setTotal(0);
    } finally {
      setLoading(false);
    }
  }, [page, status, zone, from, to]);

  useEffect(() => {
    load();
  }, [load]);

  const totalPages = Math.max(1, Math.ceil(total / limit));

  return (
    <>
      <header className="page-header">
        <h2>Incidents</h2>
        <p>Liste des signalements — cliquez une ligne pour le détail</p>
      </header>

      {error && <div className="form-error">{error}</div>}

      <div className="card">
        <div className="card-toolbar">
          <select
            value={status}
            onChange={(e) => {
              setStatus(e.target.value);
              setPage(1);
            }}
          >
            <option value="">Tous les statuts</option>
            {Object.entries(INCIDENT_STATUS_LABELS).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </select>
          <input
            type="text"
            placeholder="Zone (ex. Gombe)"
            value={zone}
            onChange={(e) => {
              setZone(e.target.value);
              setPage(1);
            }}
          />
          <input
            type="date"
            value={from}
            onChange={(e) => {
              setFrom(e.target.value);
              setPage(1);
            }}
          />
          <input
            type="date"
            value={to}
            onChange={(e) => {
              setTo(e.target.value);
              setPage(1);
            }}
          />
          <button type="button" className="btn btn-secondary" onClick={() => load()}>
            Actualiser
          </button>
        </div>

        {loading ? (
          <div className="loading">Chargement…</div>
        ) : (
          <>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Type</th>
                    <th>Zone</th>
                    <th>Statut</th>
                    <th>Gravité</th>
                    <th>Signaleur</th>
                    <th>Confirmations</th>
                    <th>Date</th>
                  </tr>
                </thead>
                <tbody>
                  {incidents.length === 0 ? (
                    <tr>
                      <td colSpan={7} className="empty">
                        Aucun incident
                      </td>
                    </tr>
                  ) : (
                    incidents.map((i) => (
                      <tr
                        key={i.id}
                        onClick={() => setSelected(i)}
                        style={{ cursor: "pointer" }}
                        className={selected?.id === i.id ? "row-selected" : undefined}
                      >
                        <td>{INCIDENT_TYPE_LABELS[i.incident_type] ?? i.incident_type}</td>
                        <td>{i.zone_name ?? "—"}</td>
                        <td>
                          <span
                            className={`badge ${
                              i.status === "active" ? "badge-danger" : "badge-warning"
                            }`}
                          >
                            {INCIDENT_STATUS_LABELS[i.status] ?? i.status}
                          </span>
                        </td>
                        <td>{SEVERITY_LABELS[i.severity] ?? i.severity}</td>
                        <td>{i.reporter}</td>
                        <td>{i.verified_by}</td>
                        <td>{new Date(i.created_at).toLocaleString("fr-FR")}</td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
            <div className="pagination">
              <span>
                {total} incident{total !== 1 ? "s" : ""} — page {page}/{totalPages}
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

      {selected && (
        <div className="card" style={{ marginTop: 16 }}>
          <div className="card-toolbar" style={{ justifyContent: "space-between" }}>
            <h3 style={{ margin: 0 }}>Détail de l&apos;incident</h3>
            <button type="button" className="btn btn-secondary" onClick={() => setSelected(null)}>
              Fermer
            </button>
          </div>
          <dl className="detail-grid">
            <div>
              <dt>Type</dt>
              <dd>{INCIDENT_TYPE_LABELS[selected.incident_type] ?? selected.incident_type}</dd>
            </div>
            <div>
              <dt>Statut</dt>
              <dd>{INCIDENT_STATUS_LABELS[selected.status] ?? selected.status}</dd>
            </div>
            <div>
              <dt>Gravité</dt>
              <dd>{SEVERITY_LABELS[selected.severity] ?? selected.severity}</dd>
            </div>
            <div>
              <dt>Zone</dt>
              <dd>{selected.zone_name ?? "—"}</dd>
            </div>
            <div>
              <dt>Signaleur</dt>
              <dd>
                {selected.reporter}
                {selected.reporter_phone ? ` (${selected.reporter_phone})` : ""}
              </dd>
            </div>
            <div>
              <dt>Confirmations</dt>
              <dd>{selected.verified_by}</dd>
            </div>
            <div>
              <dt>Position</dt>
              <dd>
                {Number.isFinite(selected.lat) && Number.isFinite(selected.lng)
                  ? `${selected.lat.toFixed(5)}, ${selected.lng.toFixed(5)}`
                  : "—"}
              </dd>
            </div>
            <div>
              <dt>Créé le</dt>
              <dd>{new Date(selected.created_at).toLocaleString("fr-FR")}</dd>
            </div>
            {selected.resolved_at && (
              <div>
                <dt>Résolu le</dt>
                <dd>{new Date(selected.resolved_at).toLocaleString("fr-FR")}</dd>
              </div>
            )}
            <div style={{ gridColumn: "1 / -1" }}>
              <dt>Description</dt>
              <dd>{selected.description?.trim() || "Aucune description"}</dd>
            </div>
          </dl>
        </div>
      )}
    </>
  );
}
