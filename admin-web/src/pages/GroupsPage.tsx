import { useCallback, useEffect, useState } from "react";
import { api, type GroupRow } from "../api/client";

export default function GroupsPage() {
  const [groups, setGroups] = useState<GroupRow[]>([]);
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);

  const limit = 20;

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.getGroups(page, limit);
      setGroups(res.data);
      setTotal(res.total);
    } finally {
      setLoading(false);
    }
  }, [page]);

  useEffect(() => {
    load();
  }, [load]);

  const totalPages = Math.max(1, Math.ceil(total / limit));

  return (
    <>
      <header className="page-header">
        <h2>Groupes de voisins</h2>
        <p>Vue d'ensemble des groupes créés sur la plateforme</p>
      </header>

      <div className="card">
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
                    <th>Code invitation</th>
                    <th>Créateur</th>
                    <th>Créé le</th>
                  </tr>
                </thead>
                <tbody>
                  {groups.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="empty">
                        Aucun groupe
                      </td>
                    </tr>
                  ) : (
                    groups.map((g) => (
                      <tr key={g.id}>
                        <td>{g.name}</td>
                        <td>{g.zone_name ?? "—"}</td>
                        <td>{g.member_count}</td>
                        <td>
                          <code>{g.invite_code}</code>
                        </td>
                        <td>
                          {g.creator_pseudo}
                          <br />
                          <small style={{ color: "var(--gris)" }}>{g.creator_phone}</small>
                        </td>
                        <td>{new Date(g.created_at).toLocaleDateString("fr-FR")}</td>
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
    </>
  );
}
