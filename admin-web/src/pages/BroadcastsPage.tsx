import { FormEvent, useEffect, useState } from "react";
import { api } from "../api/client";
import { userFacingError } from "../utils/userFacingError";

type Broadcast = {
  id: string;
  title: string;
  body: string;
  zone_name: string;
  channels: string;
  sent_count: number;
  created_at: string;
};

export default function BroadcastsPage() {
  const [rows, setRows] = useState<Broadcast[]>([]);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [zone, setZone] = useState("");
  const [channels, setChannels] = useState("fcm");
  const [error, setError] = useState("");
  const [msg, setMsg] = useState("");
  const [loading, setLoading] = useState(false);

  const load = async () => {
    try {
      const data = await api.listBroadcasts();
      setRows(Array.isArray(data) ? data : []);
    } catch (e) {
      setError(userFacingError(e, "Impossible de charger les broadcasts."));
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setError("");
    setMsg("");
    setLoading(true);
    try {
      const res = await api.createBroadcast({
        title,
        body,
        zone_name: zone,
        channels,
      });
      setMsg(`Envoyé à ${res.sent ?? 0} / ${res.targeted ?? 0} ciblés.`);
      setTitle("");
      setBody("");
      await load();
    } catch (err) {
      setError(userFacingError(err, "Envoi impossible."));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div>
      <header className="page-header">
        <h2>Broadcast commune</h2>
        <p>Alerte push/SMS aux utilisateurs liés à une commune ou un quartier</p>
      </header>
      {error && <div className="form-error">{error}</div>}
      {msg && <div className="form-success">{msg}</div>}
      <form className="form-card" onSubmit={submit} style={{ marginBottom: 24, maxWidth: 560 }}>
        <label>
          Titre
          <input value={title} onChange={(e) => setTitle(e.target.value)} required minLength={3} />
        </label>
        <label>
          Message
          <textarea value={body} onChange={(e) => setBody(e.target.value)} required minLength={3} rows={3} />
        </label>
        <label>
          Commune / quartier (ex. Gombe)
          <input value={zone} onChange={(e) => setZone(e.target.value)} required minLength={2} />
        </label>
        <label>
          Canaux
          <select value={channels} onChange={(e) => setChannels(e.target.value)}>
            <option value="fcm">Push FCM</option>
            <option value="fcm,sms">Push + SMS</option>
            <option value="sms">SMS seulement</option>
          </select>
        </label>
        <button type="submit" className="btn btn-primary" disabled={loading}>
          {loading ? "Envoi…" : "Diffuser"}
        </button>
      </form>
      <div className="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Date</th>
            <th>Titre</th>
            <th>Zone</th>
            <th>Envoyés</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.id}>
              <td>{new Date(r.created_at).toLocaleString("fr-FR")}</td>
              <td>{r.title}</td>
              <td>{r.zone_name}</td>
              <td>{r.sent_count}</td>
            </tr>
          ))}
          {rows.length === 0 && (
            <tr>
              <td colSpan={4}>Aucun broadcast</td>
            </tr>
          )}
        </tbody>
      </table>
      </div>
    </div>
  );
}
