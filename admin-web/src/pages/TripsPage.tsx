import { FormEvent, useCallback, useEffect, useState } from "react";
import {
  api,
  isSuperAdmin,
  TRIP_MODE_LABELS,
  TRIP_STATUS_LABELS,
  type SafeTripDetail,
  type SafeTripInput,
  type SafeTripMode,
  type SafeTripRow,
  type SafeTripStatus,
} from "../api/client";
import TripTrackMap from "../components/TripTrackMap";
import { useAuth } from "../context/AuthContext";
import { userFacingError } from "../utils/userFacingError";

const EMPTY_FORM: SafeTripInput = {
  user_id: "",
  origin_lat: -4.3276,
  origin_lng: 15.3136,
  dest_lat: -4.3276,
  dest_lng: 15.3136,
  dest_label: "",
  eta_minutes: 60,
  status: "active",
  trip_mode: "destination",
  transport_mode: "moto",
  vehicle_plate: "",
  vehicle_note: "",
  notify_on_delay: true,
};

function fmt(iso?: string | null) {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleString("fr-FR");
  } catch {
    return iso;
  }
}

function modeLabel(mode?: string | null) {
  if (mode === "patrol" || mode === "destination") return TRIP_MODE_LABELS[mode];
  return mode || "—";
}

function statusLabel(status?: string | null) {
  if (status && status in TRIP_STATUS_LABELS) {
    return TRIP_STATUS_LABELS[status as SafeTripStatus];
  }
  return status || "—";
}

export default function TripsPage() {
  const { user } = useAuth();
  const canDelete = isSuperAdmin(user?.role);

  const [rows, setRows] = useState<SafeTripRow[]>([]);
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [status, setStatus] = useState("");
  const [tripMode, setTripMode] = useState("");
  const [q, setQ] = useState("");
  const [qDraft, setQDraft] = useState("");

  const [showForm, setShowForm] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState<SafeTripInput>(EMPTY_FORM);
  const [saving, setSaving] = useState(false);

  const [detail, setDetail] = useState<SafeTripDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);

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
      if (tripMode) params.trip_mode = tripMode;
      if (q.trim()) params.q = q.trim();
      const res = await api.getTrips(params);
      setRows(res.data);
      setTotal(res.total);
    } catch (err) {
      setError(userFacingError(err, "Impossible de charger les trajets."));
      setRows([]);
      setTotal(0);
    } finally {
      setLoading(false);
    }
  }, [page, status, tripMode, q]);

  useEffect(() => {
    void load();
  }, [load]);

  const openCreate = () => {
    setEditId(null);
    setForm(EMPTY_FORM);
    setShowForm(true);
  };

  const openEdit = (row: SafeTripRow) => {
    setEditId(row.id);
    setForm({
      user_id: row.user_id,
      origin_lat: row.origin_lat,
      origin_lng: row.origin_lng,
      dest_lat: row.dest_lat,
      dest_lng: row.dest_lng,
      dest_label: row.dest_label || "",
      status: row.status,
      trip_mode: (row.trip_mode as SafeTripMode) || "destination",
      transport_mode: row.transport_mode || "moto",
      vehicle_plate: row.vehicle_plate || "",
      vehicle_note: row.vehicle_note || "",
      notify_on_delay: row.notify_on_delay,
    });
    setShowForm(true);
  };

  const openDetail = async (row: SafeTripRow) => {
    setDetailLoading(true);
    setError("");
    try {
      const full = await api.getTrip(row.id);
      setDetail(full);
    } catch (err) {
      setError(userFacingError(err, "Impossible de charger le détail."));
    } finally {
      setDetailLoading(false);
    }
  };

  // Live refresh while viewing an active trip on the admin map.
  useEffect(() => {
    if (!detail || detail.status !== "active") return;
    const id = detail.id;
    const timer = window.setInterval(() => {
      void api
        .getTrip(id)
        .then((full) => setDetail(full))
        .catch(() => {});
    }, 5000);
    return () => window.clearInterval(timer);
  }, [detail?.id, detail?.status]);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (saving) return;
    setSaving(true);
    setError("");
    try {
      if (editId) {
        await api.updateTrip(editId, {
          dest_label: form.dest_label,
          origin_lat: Number(form.origin_lat),
          origin_lng: Number(form.origin_lng),
          dest_lat: Number(form.dest_lat),
          dest_lng: Number(form.dest_lng),
          status: form.status,
          trip_mode: form.trip_mode,
          transport_mode: form.transport_mode,
          vehicle_plate: form.vehicle_plate || null,
          vehicle_note: form.vehicle_note || null,
          notify_on_delay: form.notify_on_delay,
          ...(form.eta_minutes != null && form.eta_minutes > 0
            ? { eta_minutes: Number(form.eta_minutes) }
            : {}),
        });
      } else {
        if (!form.user_id?.trim()) {
          setError("L'identifiant utilisateur (UUID) est requis.");
          setSaving(false);
          return;
        }
        await api.createTrip({
          user_id: form.user_id.trim(),
          origin_lat: Number(form.origin_lat),
          origin_lng: Number(form.origin_lng),
          dest_lat: Number(form.dest_lat),
          dest_lng: Number(form.dest_lng),
          dest_label: form.dest_label || null,
          eta_minutes: Number(form.eta_minutes) || 60,
          status: form.status,
          trip_mode: form.trip_mode,
          transport_mode: form.transport_mode,
          vehicle_plate: form.vehicle_plate || null,
          vehicle_note: form.vehicle_note || null,
          notify_on_delay: form.notify_on_delay,
        });
      }
      setShowForm(false);
      await load();
    } catch (err) {
      setError(userFacingError(err, "Impossible d'enregistrer le trajet."));
    } finally {
      setSaving(false);
    }
  };

  const quickStatus = async (row: SafeTripRow, next: SafeTripStatus) => {
    setError("");
    try {
      await api.updateTrip(row.id, { status: next });
      await load();
      if (detail?.id === row.id) {
        setDetail(await api.getTrip(row.id));
      }
    } catch (err) {
      setError(userFacingError(err, "Impossible de changer le statut."));
    }
  };

  const handleDelete = async (row: SafeTripRow) => {
    if (!canDelete) return;
    if (!confirm(`Supprimer définitivement le trajet « ${row.dest_label || row.id} » ?`)) {
      return;
    }
    setError("");
    try {
      await api.deleteTrip(row.id);
      if (detail?.id === row.id) setDetail(null);
      await load();
    } catch (err) {
      setError(userFacingError(err, "Impossible de supprimer le trajet."));
    }
  };

  const totalPages = Math.max(1, Math.ceil(total / limit));

  return (
    <>
      <header className="page-header">
        <h2>Trajets sécurisés</h2>
        <p>Suivi ops des trajets et patrouilles — liste, détail, création, modification, suppression</p>
      </header>

      {error && <div className="form-error">{error}</div>}

      <div className="card">
        <div className="card-toolbar" style={{ flexWrap: "wrap", gap: 8 }}>
          <button type="button" className="btn btn-primary" onClick={openCreate}>
            Nouveau trajet
          </button>
          <select
            value={status}
            onChange={(e) => {
              setStatus(e.target.value);
              setPage(1);
            }}
          >
            <option value="">Tous les statuts</option>
            {Object.entries(TRIP_STATUS_LABELS).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </select>
          <select
            value={tripMode}
            onChange={(e) => {
              setTripMode(e.target.value);
              setPage(1);
            }}
          >
            <option value="">Tous les modes</option>
            {Object.entries(TRIP_MODE_LABELS).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </select>
          <input
            type="search"
            placeholder="Recherche (pseudo, téléphone, destination…)"
            value={qDraft}
            onChange={(e) => setQDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                setQ(qDraft);
                setPage(1);
              }
            }}
            style={{ minWidth: 220 }}
          />
          <button
            type="button"
            className="btn btn-secondary"
            onClick={() => {
              setQ(qDraft);
              setPage(1);
            }}
          >
            Filtrer
          </button>
        </div>

        {loading ? (
          <div className="loading">Chargement…</div>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Créé</th>
                  <th>Voyageur</th>
                  <th>Mode</th>
                  <th>Destination</th>
                  <th>Statut</th>
                  <th>ETA</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {rows.length === 0 ? (
                  <tr>
                    <td colSpan={7} className="empty">
                      Aucun trajet
                    </td>
                  </tr>
                ) : (
                  rows.map((row) => (
                    <tr key={row.id}>
                      <td>{fmt(row.created_at)}</td>
                      <td>
                        {row.traveler_pseudo || "—"}
                        <div style={{ fontSize: 12, opacity: 0.75 }}>{row.traveler_phone}</div>
                      </td>
                      <td>{modeLabel(row.trip_mode)}</td>
                      <td>{row.dest_label || "—"}</td>
                      <td>{statusLabel(row.status)}</td>
                      <td>{fmt(row.eta_at)}</td>
                      <td style={{ whiteSpace: "nowrap" }}>
                        <button
                          type="button"
                          className="btn btn-secondary"
                          style={{ marginRight: 4 }}
                          onClick={() => void openDetail(row)}
                        >
                          Voir
                        </button>
                        <button
                          type="button"
                          className="btn btn-secondary"
                          style={{ marginRight: 4 }}
                          onClick={() => openEdit(row)}
                        >
                          Modifier
                        </button>
                        {row.status === "active" && (
                          <>
                            <button
                              type="button"
                              className="btn btn-secondary"
                              style={{ marginRight: 4 }}
                              onClick={() => void quickStatus(row, "arrived")}
                            >
                              Arrivé
                            </button>
                            <button
                              type="button"
                              className="btn btn-secondary"
                              style={{ marginRight: 4 }}
                              onClick={() => void quickStatus(row, "cancelled")}
                            >
                              Annuler
                            </button>
                          </>
                        )}
                        {canDelete && (
                          <button
                            type="button"
                            className="btn btn-danger"
                            onClick={() => void handleDelete(row)}
                          >
                            Supprimer
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

        {totalPages > 1 && (
          <div className="card-toolbar" style={{ justifyContent: "space-between" }}>
            <span style={{ fontSize: 13 }}>
              {total} trajet{total > 1 ? "s" : ""} — page {page}/{totalPages}
            </span>
            <div>
              <button
                type="button"
                className="btn btn-secondary"
                disabled={page <= 1}
                onClick={() => setPage((p) => Math.max(1, p - 1))}
              >
                Précédent
              </button>{" "}
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
        )}
      </div>

      {(detail || detailLoading) && (
        <div className="modal-overlay" onClick={() => setDetail(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 720 }}>
            <h3>Détail du trajet</h3>
            {detailLoading || !detail ? (
              <div className="loading">Chargement…</div>
            ) : (
              <>
                <dl style={{ display: "grid", gridTemplateColumns: "140px 1fr", gap: "6px 12px", fontSize: 14 }}>
                  <dt>ID</dt>
                  <dd style={{ wordBreak: "break-all" }}>{detail.id}</dd>
                  <dt>Voyageur</dt>
                  <dd>
                    {detail.traveler_pseudo} · {detail.traveler_phone}
                  </dd>
                  <dt>Mode</dt>
                  <dd>{modeLabel(detail.trip_mode)}</dd>
                  <dt>Statut</dt>
                  <dd>{statusLabel(detail.status)}</dd>
                  <dt>Destination</dt>
                  <dd>{detail.dest_label || "—"}</dd>
                  <dt>Origine</dt>
                  <dd>
                    {detail.origin_lat}, {detail.origin_lng}
                  </dd>
                  <dt>Destination GPS</dt>
                  <dd>
                    {detail.dest_lat}, {detail.dest_lng}
                  </dd>
                  <dt>Dernière position</dt>
                  <dd>
                    {detail.last_lat != null
                      ? `${detail.last_lat}, ${detail.last_lng} (${fmt(detail.last_ping_at)})`
                      : "—"}
                  </dd>
                  <dt>Départ</dt>
                  <dd>{fmt(detail.created_at)}</dd>
                  <dt>{detail.arrived_at ? "Arrivée" : "Arrivée prévue"}</dt>
                  <dd>{fmt(detail.arrived_at || detail.eta_at)}</dd>
                  <dt>Transport</dt>
                  <dd>
                    {detail.transport_mode || "—"}
                    {detail.vehicle_plate ? ` · ${detail.vehicle_plate}` : ""}
                  </dd>
                  <dt>Note véhicule</dt>
                  <dd>{detail.vehicle_note || "—"}</dd>
                  <dt>Points de tracé</dt>
                  <dd>{detail.track?.length ?? 0}</dd>
                </dl>
                <TripTrackMap trip={detail} />
                <div style={{ marginTop: 16, display: "flex", gap: 8, flexWrap: "wrap" }}>
                  <button type="button" className="btn btn-secondary" onClick={() => openEdit(detail)}>
                    Modifier
                  </button>
                  <button type="button" className="btn btn-secondary" onClick={() => setDetail(null)}>
                    Fermer
                  </button>
                </div>
              </>
            )}
          </div>
        </div>
      )}

      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 520 }}>
            <h3>{editId ? "Modifier le trajet" : "Nouveau trajet"}</h3>
            <form onSubmit={handleSubmit}>
              {!editId && (
                <div className="form-group">
                  <label>ID utilisateur (UUID)</label>
                  <input
                    value={form.user_id || ""}
                    onChange={(e) => setForm({ ...form, user_id: e.target.value })}
                    required
                    placeholder="uuid du citoyen"
                  />
                </div>
              )}
              <div className="form-group">
                <label>Libellé destination</label>
                <input
                  value={form.dest_label || ""}
                  onChange={(e) => setForm({ ...form, dest_label: e.target.value })}
                  maxLength={200}
                />
              </div>
              <div className="form-group">
                <label>Mode</label>
                <select
                  value={form.trip_mode || "destination"}
                  onChange={(e) =>
                    setForm({ ...form, trip_mode: e.target.value as SafeTripMode })
                  }
                >
                  {Object.entries(TRIP_MODE_LABELS).map(([k, v]) => (
                    <option key={k} value={k}>
                      {v}
                    </option>
                  ))}
                </select>
              </div>
              <div className="form-group">
                <label>Statut</label>
                <select
                  value={form.status || "active"}
                  onChange={(e) =>
                    setForm({ ...form, status: e.target.value as SafeTripStatus })
                  }
                >
                  {Object.entries(TRIP_STATUS_LABELS).map(([k, v]) => (
                    <option key={k} value={k}>
                      {v}
                    </option>
                  ))}
                </select>
              </div>
              <div className="form-group">
                <label>
                  {editId
                    ? "Recalculer ETA (minutes depuis maintenant, optionnel)"
                    : "Durée ETA (minutes)"}
                </label>
                <input
                  type="number"
                  min={5}
                  max={1440}
                  value={form.eta_minutes ?? ""}
                  onChange={(e) =>
                    setForm({
                      ...form,
                      eta_minutes: e.target.value === "" ? undefined : Number(e.target.value),
                    })
                  }
                  required={!editId}
                />
              </div>
              <div className="form-group" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>
                <label>
                  Origine lat
                  <input
                    type="number"
                    step="any"
                    value={form.origin_lat ?? ""}
                    onChange={(e) => setForm({ ...form, origin_lat: Number(e.target.value) })}
                    required
                  />
                </label>
                <label>
                  Origine lng
                  <input
                    type="number"
                    step="any"
                    value={form.origin_lng ?? ""}
                    onChange={(e) => setForm({ ...form, origin_lng: Number(e.target.value) })}
                    required
                  />
                </label>
                <label>
                  Dest lat
                  <input
                    type="number"
                    step="any"
                    value={form.dest_lat ?? ""}
                    onChange={(e) => setForm({ ...form, dest_lat: Number(e.target.value) })}
                    required
                  />
                </label>
                <label>
                  Dest lng
                  <input
                    type="number"
                    step="any"
                    value={form.dest_lng ?? ""}
                    onChange={(e) => setForm({ ...form, dest_lng: Number(e.target.value) })}
                    required
                  />
                </label>
              </div>
              <div className="form-group">
                <label>Transport</label>
                <select
                  value={form.transport_mode || "moto"}
                  onChange={(e) => setForm({ ...form, transport_mode: e.target.value })}
                >
                  <option value="moto">Moto</option>
                  <option value="car">Voiture</option>
                  <option value="walk">À pied</option>
                  <option value="bus">Bus</option>
                  <option value="other">Autre</option>
                </select>
              </div>
              <div className="form-group">
                <label>Plaque</label>
                <input
                  value={form.vehicle_plate || ""}
                  onChange={(e) => setForm({ ...form, vehicle_plate: e.target.value })}
                  maxLength={32}
                />
              </div>
              <div className="form-group">
                <label>Note véhicule</label>
                <input
                  value={form.vehicle_note || ""}
                  onChange={(e) => setForm({ ...form, vehicle_note: e.target.value })}
                  maxLength={500}
                />
              </div>
              <label style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12 }}>
                <input
                  type="checkbox"
                  checked={Boolean(form.notify_on_delay)}
                  onChange={(e) => setForm({ ...form, notify_on_delay: e.target.checked })}
                />
                Alerte si retard (notify_on_delay)
              </label>
              <div style={{ display: "flex", gap: 8 }}>
                <button type="submit" className="btn btn-primary" disabled={saving}>
                  {saving ? "Enregistrement…" : "Enregistrer"}
                </button>
                <button
                  type="button"
                  className="btn btn-secondary"
                  onClick={() => setShowForm(false)}
                >
                  Annuler
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </>
  );
}
