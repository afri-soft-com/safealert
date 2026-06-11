import { useCallback, useEffect, useState } from "react";
import {
  api,
  INCIDENT_STATUS_LABELS,
  SEVERITY_LABELS,
  type IncidentRow,
} from "../api/client";

export default function IncidentsPage() {
  const [incidents, setIncidents] = useState<IncidentRow[]>([]);
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [status, setStatus] = useState("");
  const [zone, setZone] = useState("");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");

  const limit = 20;

  const load = useCallback(async () => {
    setLoading(true);
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
        <p>Liste de tous les signalements (lecture seule)</p>
      </header>

      <div className="card">
        <div className="card-toolbar">
          <select value={status} onChange={(e) => { setStatus(e.target.value); setPage(1); }}>
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
            onChange={(e) => { setZone(e.target.value); setPage(1); }}
          />
          <input type="date" value={from} onChange={(e) => { setFrom(e.target.value); setPage(1); }} />
          <input type="date" value={to} onChange={(e) => { setTo(e.target.value); setPage(1); }} />
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
                      <tr key={i.id}>
                        <td>{i.incident_type}</td>
                        <td>{i.zone_name ?? "—"}</td>
                        <td>
                          <span className={`badge ${i.status === "active" ? "badge-danger" : "badge-warning"}`}>
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
    </>
  );
}
