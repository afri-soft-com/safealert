import { useCallback, useEffect, useState } from "react";
import { api, isSuperAdmin } from "../api/client";
import { useAuth } from "../context/AuthContext";
import { userFacingError } from "../utils/userFacingError";

type PrivacyForm = {
  title: string;
  version: string;
  body: string;
  format: string;
};

type HomeTile = {
  key: string;
  label: string;
  visible: boolean;
  env_enabled: boolean;
};

export default function SettingsPage() {
  const { user } = useAuth();
  const superAdmin = isSuperAdmin(user?.role);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [savingPrivacy, setSavingPrivacy] = useState(false);
  const [savingTiles, setSavingTiles] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [enabled, setEnabled] = useState(false);
  const [message, setMessage] = useState("");
  const [homeTiles, setHomeTiles] = useState<HomeTile[]>([]);
  const [privacy, setPrivacy] = useState<PrivacyForm>({
    title: "",
    version: "1.0",
    body: "",
    format: "markdown",
  });

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await api.getSettings();
      setEnabled(res.maintenance);
      setMessage(res.maintenance_message || "");
      if (Array.isArray(res.home_tiles)) {
        setHomeTiles(res.home_tiles);
      } else {
        const tilesRes = await api.getHomeTiles();
        setHomeTiles(tilesRes.tiles || []);
      }
      const priv = await api.getPrivacyAdmin();
      setPrivacy({
        title: priv.title || "",
        version: priv.version || "1.0",
        body: priv.body || "",
        format: priv.format || "markdown",
      });
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

  const savePrivacy = async () => {
    setSavingPrivacy(true);
    setError("");
    setSuccess("");
    try {
      const next = await api.setPrivacyAdmin(privacy);
      setPrivacy({
        title: next.title,
        version: next.version,
        body: next.body,
        format: next.format,
      });
      setSuccess("Politique de confidentialité enregistrée (visible sur /privacy et /privacy.html).");
    } catch (err) {
      setError(userFacingError(err, "Impossible d'enregistrer la politique."));
    } finally {
      setSavingPrivacy(false);
    }
  };

  const toggleTile = (key: string, visible: boolean) => {
    setHomeTiles((prev) =>
      prev.map((t) => (t.key === key ? { ...t, visible } : t))
    );
  };

  const saveHomeTiles = async () => {
    setSavingTiles(true);
    setError("");
    setSuccess("");
    try {
      const payload = Object.fromEntries(homeTiles.map((t) => [t.key, t.visible]));
      const next = await api.setHomeTiles(payload);
      setHomeTiles(next.tiles || []);
      setSuccess(
        "Visibilité des services enregistrée. Les citoyens verront les changements sous 2 minutes (ou au redémarrage de l'app)."
      );
    } catch (err) {
      setError(userFacingError(err, "Impossible d'enregistrer les services."));
    } finally {
      setSavingTiles(false);
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
        <p>Services accueil, maintenance et confidentialité (SuperAdmin)</p>
      </header>

      {error && <div className="form-error">{error}</div>}
      {success && <div className="form-success">{success}</div>}

      {!loading && (
        <div className="card" style={{ padding: "1.25rem", marginBottom: "1.25rem" }}>
          <h3 style={{ marginTop: 0 }}>Services SafeAlert</h3>
          <p className="form-hint" style={{ marginTop: 0 }}>
            Tuiles de l&apos;accueil citoyen (SuperAdmin). Décochez pour masquer un service
            dans l&apos;application mobile sans redéploiement.
          </p>
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: 10,
              marginTop: 12,
            }}
          >
            {homeTiles.map((tile) => (
              <label
                key={tile.key}
                className="toggle-row"
                style={{
                  justifyContent: "space-between",
                  alignItems: "center",
                  padding: "0.65rem 0.85rem",
                  background: "rgba(255,255,255,0.04)",
                  borderRadius: 8,
                  border: "1px solid var(--bleu-border)",
                }}
              >
                <span>
                  <strong>{tile.label}</strong>
                  {!tile.env_enabled && (
                    <>
                      <br />
                      <small>Désactivé côté serveur (FEATURE_*)</small>
                    </>
                  )}
                </span>
                <span style={{ display: "inline-flex", alignItems: "center", gap: 8 }}>
                  <small style={{ color: "var(--gris)" }}>Visible</small>
                  <input
                    type="checkbox"
                    checked={tile.visible}
                    onChange={(e) => toggleTile(tile.key, e.target.checked)}
                    style={{ marginTop: 0 }}
                  />
                </span>
              </label>
            ))}
          </div>
          <button
            type="button"
            className="btn btn-primary"
            style={{ marginTop: 16 }}
            disabled={savingTiles || homeTiles.length === 0}
            onClick={saveHomeTiles}
          >
            {savingTiles ? "Enregistrement…" : "Enregistrer les services"}
          </button>
        </div>
      )}

      <div className="card" style={{ padding: "1.25rem" }}>
        {loading ? (
          <div className="loading">Chargement…</div>
        ) : (
          <>
            <h3 style={{ marginTop: 0 }}>Mode maintenance</h3>
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
                  Les utilisateurs voient un écran d&apos;attente. SOS, annuaire et connexion
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
              {saving ? "Enregistrement…" : "Enregistrer la maintenance"}
            </button>
          </>
        )}
      </div>

      {!loading && (
        <div className="card" style={{ padding: "1.25rem", marginTop: "1.25rem" }}>
          <h3 style={{ marginTop: 0 }}>Politique de confidentialité</h3>
          <p className="form-hint" style={{ marginTop: 0 }}>
            Texte publié sur <a href="/privacy" target="_blank" rel="noreferrer">/privacy</a> et
            chargé par <a href="/privacy.html" target="_blank" rel="noreferrer">/privacy.html</a>{" "}
            (fallback si l’API est indisponible).
          </p>
          <div className="form-group" style={{ display: "grid", gap: 12, gridTemplateColumns: "1fr 1fr" }}>
            <div>
              <label htmlFor="priv-version">Version</label>
              <input
                id="priv-version"
                value={privacy.version}
                onChange={(e) => setPrivacy({ ...privacy, version: e.target.value })}
                style={{ width: "100%" }}
              />
            </div>
            <div>
              <label htmlFor="priv-format">Format</label>
              <select
                id="priv-format"
                value={privacy.format}
                onChange={(e) => setPrivacy({ ...privacy, format: e.target.value })}
                style={{ width: "100%" }}
              >
                <option value="markdown">Markdown</option>
                <option value="html">HTML</option>
                <option value="plain">Texte</option>
              </select>
            </div>
          </div>
          <div className="form-group">
            <label htmlFor="priv-title">Titre</label>
            <input
              id="priv-title"
              value={privacy.title}
              onChange={(e) => setPrivacy({ ...privacy, title: e.target.value })}
              style={{ width: "100%" }}
            />
          </div>
          <div className="form-group">
            <label htmlFor="priv-body">Texte</label>
            <textarea
              id="priv-body"
              rows={16}
              value={privacy.body}
              onChange={(e) => setPrivacy({ ...privacy, body: e.target.value })}
              style={{ width: "100%", fontFamily: "ui-monospace, monospace", fontSize: 13 }}
            />
          </div>
          <button
            type="button"
            className="btn btn-primary"
            disabled={savingPrivacy || !privacy.body.trim()}
            onClick={savePrivacy}
          >
            {savingPrivacy ? "Enregistrement…" : "Enregistrer la politique"}
          </button>
        </div>
      )}
    </>
  );
}
