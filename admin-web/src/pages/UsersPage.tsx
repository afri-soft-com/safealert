import { useCallback, useEffect, useState } from "react";
import { api, ROLE_LABELS, type UserRole, type UserRow } from "../api/client";
import { userFacingError } from "../utils/userFacingError";

const ROLES: UserRole[] = ["citizen", "leader", "agent", "platform_admin"];

export default function UsersPage() {
  const [users, setUsers] = useState<UserRow[]>([]);
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [sectors, setSectors] = useState<Record<string, string>>({});

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

  const totalPages = Math.max(1, Math.ceil(total / limit));

  return (
    <>
      <header className="page-header">
        <h2>Utilisateurs</h2>
        <p>Gestion des rôles et secteurs</p>
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
                    <th>Secteur</th>
                    <th>Inscription</th>
                  </tr>
                </thead>
                <tbody>
                  {users.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="empty">
                        Aucun utilisateur
                      </td>
                    </tr>
                  ) : (
                    users.map((u) => (
                      <tr key={u.id}>
                        <td>{u.pseudo}</td>
                        <td>{u.phone}</td>
                        <td>
                          <select
                            value={u.role}
                            onChange={(e) => handleRoleChange(u.id, e.target.value as UserRole)}
                          >
                            {ROLES.map((r) => (
                              <option key={r} value={r}>
                                {ROLE_LABELS[r]}
                              </option>
                            ))}
                          </select>
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
                        <td>{new Date(u.created_at).toLocaleDateString("fr-FR")}</td>
                      </tr>
                    ))
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
