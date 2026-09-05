import { FormEvent, useEffect, useState } from "react";
import { api, isSuperAdmin, type IncidentTypeInput, type IncidentTypeRow } from "../api/client";
import { useAuth } from "../context/AuthContext";
import { userFacingError } from "../utils/userFacingError";

const EMPTY_FORM: IncidentTypeInput = {
  slug: "",
  label_fr: "",
  active: true,
  sort_order: 100,
  reportable: true,
};

export default function IncidentTypesPage() {
  const { user } = useAuth();
  const canWrite = isSuperAdmin(user?.role);
  const [items, setItems] = useState<IncidentTypeRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [form, setForm] = useState<IncidentTypeInput>(EMPTY_FORM);
  const [editId, setEditId] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);

  const load = async () => {
    setLoading(true);
    setError("");
    try {
      const res = await api.getIncidentTypes();
      setItems(res.data);
    } catch (err) {
      setError(userFacingError(err, "Impossible de charger les types d'incidents."));
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

  const openEdit = (row: IncidentTypeRow) => {
    setEditId(row.id);
    setForm({
      slug: row.slug,
      label_fr: row.label_fr,
      active: row.active,
      sort_order: row.sort_order,
      reportable: row.reportable,
    });
    setShowForm(true);
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (!canWrite || saving) return;
    setSaving(true);
    setError("");
    try {
      if (editId) {
        await api.updateIncidentType(editId, {
          label_fr: form.label_fr,
          active: form.active,
          sort_order: form.sort_order,
          reportable: form.reportable,
        });
      } else {
        await api.createIncidentType(form);
      }
      setShowForm(false);
      await load();
    } catch (err) {
      setError(userFacingError(err, "Impossible d'enregistrer le type."));
    } finally {
      setSaving(false);
    }
  };

  const handleToggle = async (row: IncidentTypeRow) => {
    if (!canWrite) return;
    setError("");
    try {
      await api.updateIncidentType(row.id, { active: !row.active, label_fr: row.label_fr });
      await load();
    } catch (err) {
      setError(userFacingError(err, "Impossible de modifier le statut."));
    }
  };

  const handleDelete = async (row: IncidentTypeRow) => {
    if (!canWrite) return;
    if (row.system) return;
    if (!confirm(`Supprimer « ${row.label_fr} » ? S'il est déjà utilisé, il sera seulement désactivé.`)) {
      return;
    }
    setError("");
    try {
      const res = await api.deleteIncidentType(row.id);
      if (res.deactivated) {
        setError("");
      }
      await load();
    } catch (err) {
      setError(userFacingError(err, "Impossible de supprimer le type."));
    }
  };

  return (
    <>
      <header className="page-header">
        <h2>Types d'incidents</h2>
        <p>
          Catalogue affiché dans l'application (signalement et filtres). SOS reste un type
          système distinct.
        </p>
      </header>

      {error && <div className="form-error">{error}</div>}

      <div className="card">
        <div className="card-toolbar">
          {canWrite ? (
            <button type="button" className="btn btn-primary" onClick={openCreate}>
              Ajouter un type
            </button>
          ) : (
            <p style={{ margin: 0, fontSize: 13, opacity: 0.8 }}>
              Lecture seule — seul le super administrateur peut modifier le catalogue.
            </p>
          )}
        </div>

        {loading ? (
          <div className="loading">Chargement…</div>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Identifiant</th>
                  <th>Libellé</th>
                  <th>Ordre</th>
                  <th>Signalement</th>
                  <th>Actif</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {items.length === 0 ? (
                  <tr>
                    <td colSpan={6} className="empty">
                      Aucun type
                    </td>
                  </tr>
                ) : (
                  items.map((row) => (
                    <tr key={row.id}>
                      <td>
                        {row.slug}
                        {row.system ? " · système" : ""}
                      </td>
                      <td>{row.label_fr}</td>
                      <td>{row.sort_order}</td>
                      <td>{row.reportable ? "Oui" : "Non"}</td>
                      <td>{row.active ? "Oui" : "Non"}</td>
                      <td>
                        {canWrite && (
                          <>
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
                              className="btn btn-secondary"
                              style={{ marginRight: 4 }}
                              onClick={() => handleToggle(row)}
                            >
                              {row.active ? "Désactiver" : "Activer"}
                            </button>
                            {!row.system && (
                              <button
                                type="button"
                                className="btn btn-danger"
                                onClick={() => handleDelete(row)}
                              >
                                Supprimer
                              </button>
                            )}
                          </>
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

      {showForm && canWrite && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>{editId ? "Modifier le type" : "Nouveau type"}</h3>
            <form onSubmit={handleSubmit}>
              {!editId && (
                <div className="form-group">
                  <label>Identifiant (slug)</label>
                  <input
                    value={form.slug || ""}
                    onChange={(e) => setForm({ ...form, slug: e.target.value })}
                    placeholder="ex. inondation (généré depuis le libellé si vide)"
                  />
                </div>
              )}
              <div className="form-group">
                <label>Libellé (français)</label>
                <input
                  value={form.label_fr}
                  onChange={(e) => setForm({ ...form, label_fr: e.target.value })}
                  required
                  minLength={2}
                />
              </div>
              <div className="form-group">
                <label>Ordre d'affichage</label>
                <input
                  type="number"
                  value={form.sort_order ?? 100}
                  onChange={(e) =>
                    setForm({ ...form, sort_order: Number(e.target.value) })
                  }
                />
              </div>
              <div className="form-group">
                <label>
                  <input
                    type="checkbox"
                    checked={form.active !== false}
                    onChange={(e) => setForm({ ...form, active: e.target.checked })}
                  />{" "}
                  Actif
                </label>
              </div>
              <div className="form-group">
                <label>
                  <input
                    type="checkbox"
                    checked={form.reportable !== false}
                    onChange={(e) => setForm({ ...form, reportable: e.target.checked })}
                  />{" "}
                  Proposé dans le formulaire de signalement
                </label>
              </div>
              <div className="modal-actions">
                <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>
                  Annuler
                </button>
                <button type="submit" className="btn btn-primary" disabled={saving}>
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
