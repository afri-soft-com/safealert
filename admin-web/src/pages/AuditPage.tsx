import { useCallback, useEffect, useState } from "react";
import { api, type AuditLogRow } from "../api/client";
import { userFacingError } from "../utils/userFacingError";

export default function AuditPage() {
  const [rows, setRows] = useState<AuditLogRow[]>([]);
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const limit = 30;

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await api.getAuditLogs(page, limit, query);
      setRows(res.data);
      setTotal(res.total);
    } catch (err) {
      setError(userFacingError(err, "Impossible de charger le journal."));
      setRows([]);
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

  const totalPages = Math.max(1, Math.ceil(total / limit));

  return (
    <>
      <header className="page-header">
        <h2>Journal d&apos;audit</h2>
        <p>Actions sensibles des administrateurs (rôles, partenaires, annuaire…)</p>
      </header>

      {error && <div className="form-error">{error}</div>}

      <div className="toolbar" style={{ marginBottom: 16 }}>
        <input
          type="search"
          placeholder="Rechercher (action, acteur, entité…)"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          style={{ maxWidth: 360 }}
        />
      </div>

      {loading ? (
        <p>Chargement…</p>
      ) : (
        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Date</th>
                <th>Acteur</th>
                <th>Action</th>
                <th>Entité</th>
                <th>IP</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr>
                  <td colSpan={5}>Aucune entrée pour le moment.</td>
                </tr>
              ) : (
                rows.map((r) => (
                  <tr key={r.id}>
                    <td>{new Date(r.created_at).toLocaleString("fr-FR")}</td>
                    <td>
                      {r.actor_pseudo || "—"}
                      <div style={{ fontSize: 12, opacity: 0.7 }}>{r.actor_phone}</div>
                    </td>
                    <td>
                      <code>{r.action}</code>
                    </td>
                    <td>
                      {r.entity_type}
                      {r.entity_id ? ` · ${r.entity_id.slice(0, 8)}…` : ""}
                    </td>
                    <td>{r.ip || "—"}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}

      <div className="pager" style={{ marginTop: 16, display: "flex", gap: 12, alignItems: "center" }}>
        <button type="button" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
          Précédent
        </button>
        <span>
          Page {page} / {totalPages} ({total} au total)
        </span>
        <button type="button" disabled={page >= totalPages} onClick={() => setPage((p) => p + 1)}>
          Suivant
        </button>
      </div>
    </>
  );
}
