import { useEffect, useState } from "react";
import {
  api,
  INCIDENT_STATUS_LABELS,
  INCIDENT_TYPE_LABELS,
  SLA_STATUS_LABELS,
} from "../api/client";
import { userFacingError } from "../utils/userFacingError";

type QueueItem = {
  id: string;
  incident_type: string;
  status: string;
  zone_name: string | null;
  age_seconds: number;
  sla_status: string;
  reporter: string;
  assignee_pseudo: string | null;
  lat: number;
  lng: number;
};

type OpsPayload = {
  queue: QueueItem[];
  sla: {
    open_sos: number;
    sla_breach: number;
    avg_ack_seconds_24h: number | null;
  };
  busy_map: { zone_name: string; active_count: number; avg_lat: number; avg_lng: number }[];
  generated_at: string;
};

export default function OpsPage() {
  const [data, setData] = useState<OpsPayload | null>(null);
  const [error, setError] = useState("");
  const [exportMsg, setExportMsg] = useState("");
  const [exporting, setExporting] = useState(false);

  const load = () => {
    api
      .getOpsQueue()
      .then((payload) => {
        setData(payload);
        setError("");
      })
      .catch((err) =>
        setError(userFacingError(err, "Impossible de charger la file d'attente."))
      );
  };

  useEffect(() => {
    load();
    const t = setInterval(load, 15000);
    return () => clearInterval(t);
  }, []);

  const exportReport = async (format: "csv" | "pdf") => {
    setExporting(true);
    setExportMsg("");
    try {
      await api.downloadOpsReport(format, 7);
      setExportMsg(format === "csv" ? "Export CSV téléchargé." : "Rapport PDF téléchargé.");
    } catch (err) {
      setError(userFacingError(err, "Impossible de télécharger le rapport."));
    } finally {
      setExporting(false);
    }
  };

  return (
    <>
      <header className="page-header">
        <h2>Ops temps réel</h2>
        <p>File SOS, délais de prise en charge et zones actives</p>
      </header>

      {error && <div className="form-error">{error}</div>}
      {exportMsg && <div className="form-success">{exportMsg}</div>}

      {data && (
        <>
          <div className="stats-grid">
            <div className="stat-card accent">
              <div className="label">SOS ouverts</div>
              <div className="value">{data.sla.open_sos}</div>
            </div>
            <div className="stat-card">
              <div className="label">Délai dépassé (&gt;5 min)</div>
              <div className="value">{data.sla.sla_breach}</div>
            </div>
            <div className="stat-card">
              <div className="label">Temps moyen de prise en charge (24h)</div>
              <div className="value">
                {data.sla.avg_ack_seconds_24h != null
                  ? `${Math.round(data.sla.avg_ack_seconds_24h / 60)} min`
                  : "—"}
              </div>
            </div>
          </div>

          <h3 style={{ marginTop: 24 }}>File d&apos;attente</h3>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Type</th>
                  <th>Zone</th>
                  <th>Âge</th>
                  <th>Délai</th>
                  <th>Signalant</th>
                  <th>Assigné</th>
                  <th>Statut</th>
                </tr>
              </thead>
              <tbody>
                {data.queue.map((q) => (
                  <tr key={q.id}>
                    <td>{INCIDENT_TYPE_LABELS[q.incident_type] ?? q.incident_type}</td>
                    <td>{q.zone_name || "—"}</td>
                    <td>{Math.round(q.age_seconds / 60)} min</td>
                    <td>
                      <span className={`badge ${q.sla_status}`}>
                        {SLA_STATUS_LABELS[q.sla_status] ?? q.sla_status}
                      </span>
                    </td>
                    <td>{q.reporter}</td>
                    <td>{q.assignee_pseudo || "—"}</td>
                    <td>{INCIDENT_STATUS_LABELS[q.status] ?? q.status}</td>
                  </tr>
                ))}
                {data.queue.length === 0 && (
                  <tr>
                    <td colSpan={7}>Aucun SOS actif</td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>

          <h3 style={{ marginTop: 24 }}>Zones actives</h3>
          {data.busy_map.length === 0 ? (
            <p className="empty">Aucune zone avec activité en cours.</p>
          ) : (
            <ul>
              {data.busy_map.map((z) => (
                <li key={z.zone_name}>
                  <strong>{z.zone_name}</strong> — {z.active_count} actif(s)
                </li>
              ))}
            </ul>
          )}

          <p style={{ marginTop: 16, fontSize: 12, opacity: 0.7 }}>
            Mis à jour : {new Date(data.generated_at).toLocaleString("fr-FR")}
            {" · "}
            <button
              type="button"
              className="btn btn-secondary"
              disabled={exporting}
              onClick={() => exportReport("csv")}
              style={{ marginRight: 8 }}
            >
              Export CSV 7j
            </button>
            <button
              type="button"
              className="btn btn-secondary"
              disabled={exporting}
              onClick={() => exportReport("pdf")}
            >
              Export PDF 7j
            </button>
          </p>
        </>
      )}

      {!data && !error && <div className="loading">Chargement…</div>}
    </>
  );
}
