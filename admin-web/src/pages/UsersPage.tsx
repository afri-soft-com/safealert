import { useCallback, useEffect, useState } from "react";
import { api, isSuperAdmin, ROLE_LABELS, type UserRole, type UserRow } from "../api/client";
import { userFacingError } from "../utils/userFacingError";
import { useAuth } from "../context/AuthContext";

const BASE_ROLES: UserRole[] = ["citizen", "leader", "agent"];
const SUPER_ROLES: UserRole[] = [...BASE_ROLES, "admin", "platform_admin"];

function premiumLabel(until?: string | null): string {
  if (!until) return "—";
  const d = new Date(until);
  if (Number.isNaN(d.getTime())) return "—";
  if (d.getTime() <= Date.now()) return "expiré";
  return d.toLocaleDateString("fr-FR");
}

export default function UsersPage() {
  const { user: me } = useAuth();
  const superAdmin = isSuperAdmin(me?.role);
  const roleOptions = superAdmin ? SUPER_ROLES : BASE_ROLES;
  const [users, setUsers] = useState<UserRow[]>([]);
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [sectors, setSectors] = useState<Record<string, string>>({});
  const [busyId, setBusyId] = useState<string | null>(null);

  const limit = 20;

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await api.getUsers(page, limit, query);
      setUsers(res.data);
      setTotal(res.total);
      const map: Record<string, string> = {};
      for (const u of res.data) {
        map[u.id] = u.sector_name ?? "";
      }
      setSectors(map);
    } catch (err) {
      setError(userFacingError(err, "Impossible de charger les utilisateurs."));
      setUsers([]);
      setTotal(0);
    } finally {
      setLoading(false);
    }
  }, [page, query]);

  useEffect(() => {
    load();
  }, [load]);

  useEffect(() => {
    const t = setTimeout(() => {
      setPage(1);
      setQuery(search.trim());
    }, 350);
    return () => clearTimeout(t);
  }, [search]);

  const handleRoleChange = async (id: string, role: UserRole) => {
    try {
      await api.updateUserRole(id, role);
      await load();
    } catch (err) {
      alert(userFacingError(err, "Impossible de modifier le rôle."));
    }
  };

  const handleSectorSave = async (id: string) => {
    const value = sectors[id]?.trim() || null;
    try {
      await api.updateUserSector(id, value);
      await load();
    } catch (err) {
      alert(userFacingError(err, "Impossible de mettre à jour le secteur."));
    }
  };

  const handleGrantPremium = async (id: string) => {
    const raw = window.prompt("Nombre de jours Premium à accorder ?", "30");
    if (raw == null) return;
    const days = Math.min(365, Math.max(1, parseInt(raw, 10) || 30));
    setBusyId(id);
    try {
      await api.grantPremium(id, days);
      await load();
    } catch (err) {
      alert(userFacingError(err, "Impossible d'accorder Premium."));
    } finally {
      setBusyId(null);
    }
  };

  const handleRevokePremium = async (id: string) => {
    if (!window.confirm("Révoquer Premium pour cet utilisateur ?")) return;
    setBusyId(id);
    try {
      await api.revokePremium(id);
      await load();
    } catch (err) {
      alert(userFacingError(err, "Impossible de révoquer Premium."));
    } finally {
      setBusyId(null);
    }
  };

  const handleToggleActive = async (id: string, next: boolean) => {
    const label = next ? "réactiver" : "désactiver";
    if (!window.confirm(`Voulez-vous ${label} ce compte ?`)) return;
    setBusyId(id);
    try {
      await api.setUserActive(id, next);
      await load();
    } catch (err) {
      alert(userFacingError(err, "Impossible de mettre à jour le compte."));
    } finally {
      setBusyId(null);
    }
  };

  const totalPages = Math.max(1, Math.ceil(total / limit));

  return (
    <>
      <header className="page-header">
        <h2>Utilisateurs</h2>
        <p>Gestion des rôles, comptes et Premium</p>
      </header>

      {error && <div className="form-error">{error}</div>}

      <div className="card">
        <div className="card-toolbar">
          <input
            type="search"
            placeholder="Rechercher (téléphone, pseudo, secteur)…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={{ flex: 1, minWidth: 200 }}
          />
        </div>

        {loading ? (
          <div className="loading">Chargement…</div>
        ) : (
          <>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Pseudo</th>
                    <th>Téléphone</th>
                    <th>Rôle</th>
                    <th>Compte</th>
                    <th>Secteur</th>
                    <th>Premium</th>
                    <th>Inscription</th>
                  </tr>
                </thead>
                <tbody>
                  {users.length === 0 ? (
                    <tr>
                      <td colSpan={7} className="empty">
                        Aucun utilisateur
                      </td>
                    </tr>
                  ) : (
                    users.map((u) => {
                      const active =
                        u.premium_until &&
                        new Date(u.premium_until).getTime() > Date.now();
                      return (
                        <tr key={u.id}>
                          <td>{u.pseudo}</td>
                          <td>{u.phone}</td>
                          <td>
                            <select
                              value={u.role}
                              onChange={(e) =>
                                handleRoleChange(u.id, e.target.value as UserRole)
                              }
                            >
                              {(roleOptions.includes(u.role)
                                ? roleOptions
                                : [...roleOptions, u.role]
                              ).map((r) => (
                                <option key={r} value={r}>
                                  {ROLE_LABELS[r] ?? r}
                                </option>
                              ))}
                            </select>
                          </td>
                          <td>
                            {superAdmin ? (
                              <button
                                type="button"
                                className="btn btn-secondary"
                                style={{ padding: "0.25rem 0.45rem" }}
                                disabled={busyId === u.id || u.id === me?.id}
                                onClick={() =>
                                  handleToggleActive(u.id, u.is_active === false)
                                }
                              >
                                {u.is_active === false ? "Activer" : "Désactiver"}
                              </button>
                            ) : u.is_active === false ? (
                              "Inactif"
                            ) : (
                              "Actif"
                            )}
                          </td>
                          <td>
                            <input
                              className="inline-input"
                              value={sectors[u.id] ?? ""}
                              onChange={(e) =>
                                setSectors((s) => ({ ...s, [u.id]: e.target.value }))
                              }
                              placeholder="Secteur"
                            />
                            <button
                              type="button"
                              className="btn btn-secondary"
                              style={{ marginLeft: 4, padding: "0.35rem 0.5rem" }}
                              onClick={() => handleSectorSave(u.id)}
                            >
                              ✓
                            </button>
                          </td>
                          <td>
                            <div style={{ fontSize: "0.85rem", marginBottom: 4 }}>
                              {active ? (
                                <strong>jusqu&apos;au {premiumLabel(u.premium_until)}</strong>
                              ) : (
                                premiumLabel(u.premium_until)
                              )}
                            </div>
                            <button
                              type="button"
                              className="btn btn-secondary"
                              style={{ padding: "0.25rem 0.45rem", marginRight: 4 }}
                              disabled={busyId === u.id}
                              onClick={() => handleGrantPremium(u.id)}
                            >
                              Accorder
                            </button>
                            <button
                              type="button"
                              className="btn btn-secondary"
                              style={{ padding: "0.25rem 0.45rem" }}
                              disabled={busyId === u.id || !u.premium_until}
                              onClick={() => handleRevokePremium(u.id)}
                            >
                              Révoquer
                            </button>
                          </td>
                          <td>{new Date(u.created_at).toLocaleDateString("fr-FR")}</td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>
            <div className="pagination">
              <span>
                {total} utilisateur{total !== 1 ? "s" : ""} — page {page}/{totalPages}
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
