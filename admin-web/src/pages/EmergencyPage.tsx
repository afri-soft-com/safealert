import { FormEvent, useEffect, useState } from "react";
import { api, type EmergencyInput, type EmergencyRow } from "../api/client";
import { userFacingError } from "../utils/userFacingError";

const EMPTY_FORM: EmergencyInput = {
  country_code: "CD",
  service_name: "",
  service_type: "police",
  phone_number: "",
  icon: "📞",
  is_offline_available: true,
};

export default function EmergencyPage() {
  const [items, setItems] = useState<EmergencyRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [form, setForm] = useState<EmergencyInput>(EMPTY_FORM);
  const [editId, setEditId] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);

  const load = async () => {
    setLoading(true);
    setError("");
    try {
      const res = await api.getEmergencyNumbers();
      setItems(res.data);
    } catch (err) {
      setError(userFacingError(err, "Impossible de charger l'annuaire."));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load();
  }, []);

  const openCreate = () => {
    setEditId(null);
    setForm(EMPTY_FORM);
    setShowForm(true);
  };

  const openEdit = (row: EmergencyRow) => {
    setEditId(row.id);
    setForm({
      country_code: row.country_code,
      service_name: row.service_name,
      service_type: row.service_type,
      phone_number: row.phone_number,
      icon: row.icon,
      is_offline_available: row.is_offline_available,
    });
    setShowForm(true);
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (saving) return;
    setSaving(true);
    setError("");
    try {
      if (editId) {
        await api.updateEmergencyNumber(editId, form);
      } else {
        await api.createEmergencyNumber(form);
      }
      setShowForm(false);
      await load();
    } catch (err) {
      setError(userFacingError(err, "Impossible d'enregistrer le numéro."));
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (id: string, name: string) => {
    if (!confirm(`Supprimer « ${name} » ?`)) return;
    setError("");
    try {
      await api.deleteEmergencyNumber(id);
      await load();
    } catch (err) {
      setError(userFacingError(err, "Impossible de supprimer le numéro."));
    }
  };

  return (
    <>
      <header className="page-header">
        <h2>Annuaire d'urgence</h2>
        <p>Numéros d'urgence affichés dans l'application mobile</p>
      </header>

      {error && <div className="form-error">{error}</div>}

      <div className="card">
        <div className="card-toolbar">
          <button type="button" className="btn btn-primary" onClick={openCreate}>
            Ajouter un numéro
          </button>
        </div>

        {loading ? (
          <div className="loading">Chargement…</div>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Pays</th>
                  <th>Service</th>
                  <th>Type</th>
                  <th>Numéro</th>
                  <th>Hors-ligne</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {items.length === 0 ? (
                  <tr>
                    <td colSpan={6} className="empty">
                      Aucun numéro
                    </td>
                  </tr>
                ) : (
                  items.map((row) => (
                    <tr key={row.id}>
                      <td>{row.country_code}</td>
                      <td>
                        {row.icon} {row.service_name}
                      </td>
                      <td>{row.service_type}</td>
                      <td>{row.phone_number}</td>
                      <td>{row.is_offline_available ? "Oui" : "Non"}</td>
                      <td>
                        <button
                          type="button"
                          className="btn btn-secondary"
                          style={{ marginRight: 4 }}
                          onClick={() => openEdit(row)}
                        >
                          Modifier
                        </button>
                        <button
                          type="button"
                          className="btn btn-danger"
                          onClick={() => handleDelete(row.id, row.service_name)}
                        >
                          Supprimer
                        </button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>{editId ? "Modifier" : "Nouveau numéro"}</h3>
            <form onSubmit={handleSubmit}>
              <div className="form-group">
                <label>Code pays</label>
                <input
                  value={form.country_code}
                  onChange={(e) => setForm({ ...form, country_code: e.target.value })}
                  maxLength={5}
                  required
                />
              </div>
              <div className="form-group">
                <label>Nom du service</label>
                <input
                  value={form.service_name}
                  onChange={(e) => setForm({ ...form, service_name: e.target.value })}
                  required
                />
              </div>
              <div className="form-group">
                <label>Type (police, pompiers, etc.)</label>
                <input
                  value={form.service_type}
                  onChange={(e) => setForm({ ...form, service_type: e.target.value })}
                  required
                />
              </div>
              <div className="form-group">
                <label>Numéro</label>
                <input
                  value={form.phone_number}
                  onChange={(e) => setForm({ ...form, phone_number: e.target.value })}
                  required
                />
              </div>
              <div className="form-group">
                <label>Icône (emoji)</label>
                <input
                  value={form.icon}
                  onChange={(e) => setForm({ ...form, icon: e.target.value })}
                />
              </div>
              <div className="form-group">
                <label>
                  <input
                    type="checkbox"
                    checked={form.is_offline_available}
                    onChange={(e) =>
                      setForm({ ...form, is_offline_available: e.target.checked })
                    }
                  />{" "}
                  Disponible hors-ligne
                </label>
              </div>
              <div className="modal-actions">
                <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>
                  Annuler
                </button>
                <button type="submit" className="btn btn-primary">
                  Enregistrer
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </>
  );
}
