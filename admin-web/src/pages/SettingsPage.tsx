import { useCallback, useEffect, useState } from "react";
import { api, isSuperAdmin } from "../api/client";
import { useAuth } from "../context/AuthContext";
import { userFacingError } from "../utils/userFacingError";

export default function SettingsPage() {
  const { user } = useAuth();
  const superAdmin = isSuperAdmin(user?.role);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [enabled, setEnabled] = useState(false);
  const [message, setMessage] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await api.getSettings();
      setEnabled(res.maintenance);
      setMessage(res.maintenance_message || "");
    } catch (err) {
      setError(userFacingError(err, "Impossible de charger les réglages."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const save = async () => {
    setSaving(true);
    setError("");
    setSuccess("");
    try {
      const res = await api.setMaintenance(enabled, message);
      setEnabled(res.maintenance);
      setMessage(res.maintenance_message);
      setSuccess(
        res.maintenance
          ? "Mode maintenance activé. Les citoyens verront l'écran d'attente."
          : "Mode maintenance désactivé. La plateforme est à nouveau ouverte."
      );
    } catch (err) {
      setError(userFacingError(err, "Impossible d'enregistrer."));
    } finally {
      setSaving(false);
    }
  };

  if (!superAdmin) {
    return (
      <>
        <header className="page-header">
          <h2>Réglages</h2>
          <p>Réservé au super administrateur.</p>
        </header>
      </>
    );
  }

  return (
    <>
      <header className="page-header">
        <h2>Réglages</h2>
        <p>Mode maintenance de la plateforme</p>
      </header>

      {error && <div className="form-error">{error}</div>}
      {success && <div className="form-success">{success}</div>}

      <div className="card" style={{ padding: "1.25rem" }}>
        {loading ? (
          <div className="loading">Chargement…</div>
        ) : (
          <>
            <label className="toggle-row">
              <input
                type="checkbox"
                checked={enabled}
                onChange={(e) => setEnabled(e.target.checked)}
              />
              <span>
                <strong>Activer le mode maintenance</strong>
                <br />
                <small>
                  Les utilisateurs voient un écran d'attente. SOS, annuaire et connexion
                  administrateur restent disponibles.
                </small>
              </span>
            </label>
            <div className="form-group" style={{ marginTop: 16 }}>
              <label htmlFor="maint-msg">Message affiché</label>
              <textarea
                id="maint-msg"
                rows={3}
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                style={{ width: "100%" }}
              />
            </div>
            <button type="button" className="btn btn-primary" disabled={saving} onClick={save}>
              {saving ? "Enregistrement…" : "Enregistrer"}
            </button>
          </>
        )}
      </div>
    </>
  );
}
