import { FormEvent, useCallback, useEffect, useState } from "react";
import {
  api,
  isSuperAdmin,
  type GroupDetail,
  type GroupInput,
  type GroupRow,
} from "../api/client";
import { useAuth } from "../context/AuthContext";
import { userFacingError } from "../utils/userFacingError";

const EMPTY_FORM: GroupInput = {
  name: "",
  description: "",
  zone_name: "",
  is_public: true,
  admin_phones: [],
};

export default function GroupsPage() {
  const { user } = useAuth();
  const canWrite = isSuperAdmin(user?.role);

  const [groups, setGroups] = useState<GroupRow[]>([]);
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [q, setQ] = useState("");
  const [qDraft, setQDraft] = useState("");

  const [showForm, setShowForm] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState<GroupInput>(EMPTY_FORM);
  const [adminPhonesText, setAdminPhonesText] = useState("");
  const [saving, setSaving] = useState(false);

  const [detail, setDetail] = useState<GroupDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [newAdminPhone, setNewAdminPhone] = useState("");
  const [adminBusy, setAdminBusy] = useState(false);

  const limit = 20;

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await api.getGroups(page, limit, q);
      setGroups(res.data);
      setTotal(res.total);
    } catch (err) {
      setError(userFacingError(err, "Impossible de charger les groupes."));
      setGroups([]);
      setTotal(0);
    } finally {
      setLoading(false);
    }
  }, [page, q]);

  useEffect(() => {
    void load();
  }, [load]);

  const openCreate = () => {
    setEditId(null);
    setForm(EMPTY_FORM);
    setAdminPhonesText("");
    setShowForm(true);
  };

  const openEdit = (row: GroupRow) => {
    setEditId(row.id);
    setForm({
      name: row.name,
      description: row.description || "",
      zone_name: row.zone_name || "",
      is_public: row.is_public !== false,
    });
    setAdminPhonesText("");
    setShowForm(true);
  };

  const openDetail = async (row: GroupRow) => {
    setDetailLoading(true);
    setError("");
    setNewAdminPhone("");
    try {
      setDetail(await api.getGroup(row.id));
    } catch (err) {
      setError(userFacingError(err, "Impossible de charger le détail."));
    } finally {
      setDetailLoading(false);
    }
  };

  const refreshDetail = async (id: string) => {
    try {
      setDetail(await api.getGroup(id));
      await load();
    } catch {
      /* keep current */
    }
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (!canWrite || saving) return;
    setSaving(true);
    setError("");
    try {
      const phones = adminPhonesText
        .split(/[\n,;]+/)
        .map((p) => p.trim())
        .filter(Boolean);
      if (editId) {
        await api.updateGroup(editId, {
          name: form.name,
          description: form.description || null,
          zone_name: form.zone_name || null,
          is_public: form.is_public,
        });
      } else {
        await api.createGroup({
          name: form.name,
          description: form.description || null,
          zone_name: form.zone_name || null,
          is_public: form.is_public,
          admin_phones: phones,
        });
      }
      setShowForm(false);
      await load();
    } catch (err) {
      setError(userFacingError(err, "Impossible d'enregistrer le groupe."));
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (row: GroupRow) => {
    if (!canWrite) return;
    if (
      !confirm(
        `Supprimer définitivement le groupe « ${row.name} » ? Membres, messages et alertes associés seront aussi retirés.`
      )
    ) {
      return;
    }
    setError("");
    try {
      await api.deleteGroup(row.id);
      if (detail?.id === row.id) setDetail(null);
      await load();
    } catch (err) {
      setError(userFacingError(err, "Impossible de supprimer le groupe."));
    }
  };

  const handleRegenInvite = async (id: string) => {
    if (!canWrite) return;
    if (!confirm("Régénérer le code d'invitation ? L'ancien code ne fonctionnera plus.")) return;
    setError("");
    try {
      await api.updateGroup(id, { regenerate_invite: true });
      await refreshDetail(id);
    } catch (err) {
      setError(userFacingError(err, "Impossible de régénérer le code."));
    }
  };

  const handleAddAdmin = async () => {
    if (!canWrite || !detail || !newAdminPhone.trim()) return;
    setAdminBusy(true);
    setError("");
    try {
      await api.addGroupAdmin(detail.id, { phone: newAdminPhone.trim() });
      setNewAdminPhone("");
      await refreshDetail(detail.id);
    } catch (err) {
      setError(userFacingError(err, "Impossible d'ajouter l'administrateur."));
    } finally {
      setAdminBusy(false);
    }
  };

  const handleSetRole = async (userId: string, role: "admin" | "member") => {
    if (!canWrite || !detail) return;
    setAdminBusy(true);
    setError("");
    try {
      await api.setGroupMemberRole(detail.id, userId, role);
      await refreshDetail(detail.id);
    } catch (err) {
      setError(userFacingError(err, "Impossible de modifier le rôle."));
    } finally {
      setAdminBusy(false);
    }
  };

  const handleRemoveMember = async (userId: string, label: string) => {
    if (!canWrite || !detail) return;
    if (!confirm(`Retirer ${label} du groupe ?`)) return;
    setAdminBusy(true);
    setError("");
    try {
      await api.removeGroupMember(detail.id, userId);
      await refreshDetail(detail.id);
    } catch (err) {
      setError(userFacingError(err, "Impossible de retirer le membre."));
    } finally {
      setAdminBusy(false);
    }
  };

  const totalPages = Math.max(1, Math.ceil(total / limit));

  return (
    <>
      <header className="page-header">
        <h2>Groupes de voisins</h2>
        <p>
          {canWrite
            ? "CRUD des groupes — créez un groupe et ajoutez d'autres administrateurs de quartier"
            : "Vue d'ensemble des groupes (lecture seule)"}
        </p>
      </header>

      {error && <div className="form-error">{error}</div>}

      <div className="card">
        <div className="card-toolbar" style={{ flexWrap: "wrap", gap: 8 }}>
          {canWrite && (
            <button type="button" className="btn btn-primary" onClick={openCreate}>
              Nouveau groupe
            </button>
          )}
          <input
            type="search"
            placeholder="Recherche (nom, zone, code, créateur…)"
            value={qDraft}
            onChange={(e) => setQDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                setQ(qDraft);
                setPage(1);
              }
            }}
            style={{ minWidth: 240 }}
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
          <>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Nom</th>
                    <th>Zone</th>
                    <th>Membres</th>
                    <th>Admins</th>
                    <th>Code</th>
                    <th>Public</th>
                    <th>Créateur</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {groups.length === 0 ? (
                    <tr>
                      <td colSpan={8} className="empty">
                        Aucun groupe
                      </td>
                    </tr>
                  ) : (
                    groups.map((g) => (
                      <tr key={g.id}>
                        <td>{g.name}</td>
                        <td>{g.zone_name ?? "—"}</td>
                        <td>{g.member_count}</td>
                        <td>{g.admin_count ?? "—"}</td>
                        <td>
                          <code>{g.invite_code}</code>
                        </td>
                        <td>{g.is_public === false ? "Non" : "Oui"}</td>
                        <td>
                          {g.creator_pseudo}
                          <br />
                          <small style={{ color: "var(--gris)" }}>{g.creator_phone}</small>
                        </td>
                        <td style={{ whiteSpace: "nowrap" }}>
                          <button
                            type="button"
                            className="btn btn-secondary"
                            style={{ marginRight: 4 }}
                            onClick={() => void openDetail(g)}
                          >
                            Gérer
                          </button>
                          {canWrite && (
                            <>
                              <button
                                type="button"
                                className="btn btn-secondary"
                                style={{ marginRight: 4 }}
                                onClick={() => openEdit(g)}
                              >
                                Modifier
                              </button>
                              <button
                                type="button"
                                className="btn btn-danger"
                                onClick={() => void handleDelete(g)}
                              >
                                Supprimer
                              </button>
                            </>
                          )}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
            <div className="pagination">
              <span>
                {total} groupe{total !== 1 ? "s" : ""} — page {page}/{totalPages}
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

      {(detail || detailLoading) && (
        <div className="modal-overlay" onClick={() => setDetail(null)}>
          <div
            className="modal"
            onClick={(e) => e.stopPropagation()}
            style={{ maxWidth: 640 }}
          >
            <h3>Groupe — {detail?.name || "…"}</h3>
            {detailLoading || !detail ? (
              <div className="loading">Chargement…</div>
            ) : (
              <>
                <p style={{ fontSize: 13, marginTop: 0 }}>
                  Code <code>{detail.invite_code}</code>
                  {canWrite && (
                    <>
                      {" "}
                      <button
                        type="button"
                        className="btn btn-secondary"
                        style={{ fontSize: 12, padding: "2px 8px" }}
                        onClick={() => void handleRegenInvite(detail.id)}
                      >
                        Régénérer
                      </button>
                    </>
                  )}
                  <br />
                  Zone : {detail.zone_name || "—"} · Membres : {detail.member_count} ·{" "}
                  {detail.is_public === false ? "Privé" : "Public"}
                </p>
                {detail.description && (
                  <p style={{ fontSize: 13, color: "var(--gris)" }}>{detail.description}</p>
                )}

                {canWrite && (
                  <div
                    style={{
                      display: "flex",
                      gap: 8,
                      marginBottom: 12,
                      flexWrap: "wrap",
                      alignItems: "center",
                    }}
                  >
                    <input
                      type="tel"
                      placeholder="Téléphone du nouvel admin (+243…)"
                      value={newAdminPhone}
                      onChange={(e) => setNewAdminPhone(e.target.value)}
                      style={{ flex: 1, minWidth: 200 }}
                    />
                    <button
                      type="button"
                      className="btn btn-primary"
                      disabled={adminBusy || !newAdminPhone.trim()}
                      onClick={() => void handleAddAdmin()}
                    >
                      Ajouter admin
                    </button>
                  </div>
                )}

                <div className="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th>Membre</th>
                        <th>Rôle groupe</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody>
                      {(detail.members || []).map((m) => (
                        <tr key={m.id}>
                          <td>
                            {m.pseudo}
                            <br />
                            <small style={{ color: "var(--gris)" }}>{m.phone}</small>
                          </td>
                          <td>{m.role === "admin" ? "Administrateur" : "Membre"}</td>
                          <td style={{ whiteSpace: "nowrap" }}>
                            {canWrite && (
                              <>
                                {m.role === "admin" ? (
                                  <button
                                    type="button"
                                    className="btn btn-secondary"
                                    style={{ marginRight: 4 }}
                                    disabled={adminBusy}
                                    onClick={() => void handleSetRole(m.user_id, "member")}
                                  >
                                    Rétrograder
                                  </button>
                                ) : (
                                  <button
                                    type="button"
                                    className="btn btn-secondary"
                                    style={{ marginRight: 4 }}
                                    disabled={adminBusy}
                                    onClick={() => void handleSetRole(m.user_id, "admin")}
                                  >
                                    Promouvoir admin
                                  </button>
                                )}
                                <button
                                  type="button"
                                  className="btn btn-danger"
                                  disabled={adminBusy}
                                  onClick={() =>
                                    void handleRemoveMember(m.user_id, m.pseudo || m.phone)
                                  }
                                >
                                  Retirer
                                </button>
                              </>
                            )}
                          </td>
                        </tr>
                      ))}
                      {(detail.members || []).length === 0 && (
                        <tr>
                          <td colSpan={3} className="empty">
                            Aucun membre
                          </td>
                        </tr>
                      )}
                    </tbody>
                  </table>
                </div>

                <div style={{ marginTop: 16 }}>
                  <button type="button" className="btn btn-secondary" onClick={() => setDetail(null)}>
                    Fermer
                  </button>
                </div>
              </>
            )}
          </div>
        </div>
      )}

      {showForm && canWrite && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>{editId ? "Modifier le groupe" : "Nouveau groupe de voisins"}</h3>
            <form onSubmit={handleSubmit}>
              <div className="form-group">
                <label>Nom</label>
                <input
                  value={form.name}
                  onChange={(e) => setForm({ ...form, name: e.target.value })}
                  required
                  minLength={2}
                  maxLength={100}
                />
              </div>
              <div className="form-group">
                <label>Zone / quartier</label>
                <input
                  value={form.zone_name || ""}
                  onChange={(e) => setForm({ ...form, zone_name: e.target.value })}
                  maxLength={100}
                  placeholder="Ex. Gombe, Lingwala…"
                />
              </div>
              <div className="form-group">
                <label>Description</label>
                <textarea
                  value={form.description || ""}
                  onChange={(e) => setForm({ ...form, description: e.target.value })}
                  rows={3}
                />
              </div>
              <label style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12 }}>
                <input
                  type="checkbox"
                  checked={form.is_public !== false}
                  onChange={(e) => setForm({ ...form, is_public: e.target.checked })}
                />
                Groupe public (demandes d&apos;adhésion sans code)
              </label>
              {!editId && (
                <div className="form-group">
                  <label>Admins supplémentaires (téléphones, un par ligne)</label>
                  <textarea
                    value={adminPhonesText}
                    onChange={(e) => setAdminPhonesText(e.target.value)}
                    rows={3}
                    placeholder={"+24381…\n+24399…"}
                  />
                  <small style={{ color: "var(--gris)" }}>
                    Les comptes doivent déjà exister. Vous serez aussi admin du groupe.
                  </small>
                </div>
              )}
              <div className="modal-actions">
                <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>
                  Annuler
                </button>
                <button type="submit" className="btn btn-primary" disabled={saving}>
                  {saving ? "Enregistrement…" : "Enregistrer"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </>
  );
}
