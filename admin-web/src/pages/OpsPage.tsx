import { useEffect, useState } from "react";
import { api } from "../api/client";

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

  const load = () => {
    api
      .getOpsQueue()
      .then(setData)
      .catch(() => setError("Impossible de charger la file ops (rôle leader/admin requis)"));
  };

  useEffect(() => {
    load();
    const t = setInterval(load, 15000);
    return () => clearInterval(t);
  }, []);

  return (
    <>
      <header className="page-header">
        <h2>Ops temps réel</h2>
        <p>File SOS, SLA et carte d&apos;activité — SafeAlert</p>
      </header>

      {error && <div className="form-error">{error}</div>}

      {data && (
        <>
          <div className="stats-grid">
            <div className="stat-card accent">
              <div className="label">SOS ouverts</div>
              <div className="value">{data.sla.open_sos}</div>
            </div>
            <div className="stat-card">
              <div className="label">SLA dépassée (&gt;5 min)</div>
              <div className="value">{data.sla.sla_breach}</div>
            </div>
            <div className="stat-card">
              <div className="label">Ack moyen (24h)</div>
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
                  <th>SLA</th>
                  <th>Signalant</th>
                  <th>Assigné</th>
                  <th>Statut</th>
                </tr>
              </thead>
              <tbody>
                {data.queue.map((q) => (
                  <tr key={q.id}>
                    <td>{q.incident_type}</td>
                    <td>{q.zone_name || "—"}</td>
                    <td>{Math.round(q.age_seconds / 60)} min</td>
                    <td>
                      <span className={`badge ${q.sla_status}`}>{q.sla_status}</span>
                    </td>
                    <td>{q.reporter}</td>
                    <td>{q.assignee_pseudo || "—"}</td>
                    <td>{q.status}</td>
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

          <h3 style={{ marginTop: 24 }}>Zones occupées</h3>
          <ul>
            {data.busy_map.map((z) => (
              <li key={z.zone_name}>
                <strong>{z.zone_name}</strong> — {z.active_count} actif(s)
              </li>
            ))}
          </ul>

          <p style={{ marginTop: 16, fontSize: 12, opacity: 0.7 }}>
            Mis à jour : {new Date(data.generated_at).toLocaleString("fr-FR")}
            {" · "}
            <a href={`${import.meta.env.VITE_API_BASE_URL || "/api"}/ops/reports/sector?format=csv&days=7`}>
              Export CSV 7j
            </a>
          </p>
        </>
      )}

      {!data && !error && <div className="loading">Chargement…</div>}
    </>
  );
}
