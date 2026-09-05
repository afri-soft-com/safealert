import { FormEvent, useState } from "react";
import { Navigate } from "react-router-dom";
import { ApiError, api } from "../api/client";
import { useAuth } from "../context/AuthContext";
import { userFacingError } from "../utils/userFacingError";

function needsPseudo(err: unknown): boolean {
  if (!(err instanceof ApiError) && !(err instanceof Error)) return false;
  return /pseudo\s+requis/i.test(err.message);
}

export default function LoginPage() {
  const { isAuthenticated, ready, login } = useAuth();
  const [phone, setPhone] = useState("+243");
  const [code, setCode] = useState("");
  const [pseudo, setPseudo] = useState("");
  const [needPseudo, setNeedPseudo] = useState(false);
  const [step, setStep] = useState<"phone" | "code">("phone");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [devHint, setDevHint] = useState("");

  if (!ready) return <div className="loading">Chargement…</div>;
  if (isAuthenticated) return <Navigate to="/" replace />;

  const handleRequestCode = async (e: FormEvent) => {
    e.preventDefault();
    setError("");
    setDevHint("");
    setNeedPseudo(false);
    setPseudo("");
    setLoading(true);
    try {
      const res = await api.requestCode(phone.trim());
      // Never surface OTP in production builds; local/dev only.
      if (!import.meta.env.PROD && res.devCode) {
        setDevHint(`Code de test : ${res.devCode}`);
        setCode(res.devCode);
      }
      setStep("code");
    } catch (err) {
      setError(userFacingError(err, "Impossible d'envoyer le code. Réessayez."));
    } finally {
      setLoading(false);
    }
  };

  const handleVerify = async (e: FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await login(phone.trim(), code.trim(), needPseudo ? pseudo.trim() : undefined);
    } catch (err) {
      if (needsPseudo(err)) {
        setNeedPseudo(true);
        setError("Choisissez un pseudo pour créer votre compte administrateur, puis réessayez.");
      } else {
        setError(userFacingError(err, "Connexion impossible. Vérifiez le code."));
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="login-page">
      <div className="login-card">
        <h1>SafeAlert Admin</h1>
        <p className="subtitle">Connexion réservée aux administrateurs</p>

        {error && <div className="form-error">{error}</div>}

        {step === "phone" ? (
          <form onSubmit={handleRequestCode}>
            <div className="form-group">
              <label htmlFor="phone">Numéro de téléphone</label>
              <input
                id="phone"
                type="tel"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="+243971163574"
                required
              />
            </div>
            <button type="submit" className="btn btn-primary" style={{ width: "100%" }} disabled={loading}>
              {loading ? "Envoi…" : "Recevoir le code"}
            </button>
          </form>
        ) : (
          <form onSubmit={handleVerify}>
            <div className="form-group">
              <label htmlFor="code">Code à 6 chiffres</label>
              <input
                id="code"
                type="text"
                inputMode="numeric"
                maxLength={6}
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
                required
              />
            </div>
            {needPseudo && (
              <div className="form-group">
                <label htmlFor="pseudo">Pseudo</label>
                <input
                  id="pseudo"
                  type="text"
                  value={pseudo}
                  onChange={(e) => setPseudo(e.target.value)}
                  placeholder="Ex. AdminSafeAlert"
                  autoComplete="nickname"
                  maxLength={50}
                  required
                />
                <p className="form-hint">Première connexion : un pseudo est requis pour créer le compte.</p>
              </div>
            )}
            {devHint && <p className="form-hint">{devHint}</p>}
            <button
              type="submit"
              className="btn btn-primary"
              style={{ width: "100%" }}
              disabled={loading || (needPseudo && !pseudo.trim())}
            >
              {loading ? "Vérification…" : "Se connecter"}
            </button>
            <button
              type="button"
              className="btn btn-secondary"
              style={{ width: "100%", marginTop: "0.5rem" }}
              onClick={() => {
                setStep("phone");
                setCode("");
                setPseudo("");
                setNeedPseudo(false);
                setDevHint("");
              }}
            >
              Changer de numéro
            </button>
          </form>
        )}

        <p className="form-hint" style={{ marginTop: "1.5rem" }}>
          Partenaire API ?{" "}
          <a href="/portail-partenaire">Accéder au portail partenaire</a>
        </p>
        <p className="form-hint">
          <a href="/manuel.html">Manuel utilisateur</a>
          {" · "}
          <a href="/cgu.html">CGU</a>
          {" · "}
          <a href="/privacy.html">Confidentialité</a>
        </p>
      </div>
    </div>
  );
}
