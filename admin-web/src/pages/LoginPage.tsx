import { FormEvent, useState } from "react";
import { Navigate } from "react-router-dom";
import { api } from "../api/client";
import { useAuth } from "../context/AuthContext";
import { userFacingError } from "../utils/userFacingError";

const isDev = import.meta.env.DEV;

export default function LoginPage() {
  const { isAuthenticated, ready, login } = useAuth();
  const [phone, setPhone] = useState("+243");
  const [code, setCode] = useState("");
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
    setLoading(true);
    try {
      const res = await api.requestCode(phone.trim());
      if (isDev && res.devCode) {
        setDevHint(`Mode développement — code : ${res.devCode}`);
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
      await login(phone.trim(), code.trim());
    } catch (err) {
      setError(userFacingError(err, "Connexion impossible. Vérifiez le code."));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="login-page">
      <div className="login-card">
        <h1>SafeAlert Admin</h1>
        <p className="subtitle">Connexion réservée aux administrateurs plateforme</p>

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
            {devHint && <p className="form-hint">{devHint}</p>}
            <button type="submit" className="btn btn-primary" style={{ width: "100%" }} disabled={loading}>
              {loading ? "Vérification…" : "Se connecter"}
            </button>
            <button
              type="button"
              className="btn btn-secondary"
              style={{ width: "100%", marginTop: "0.5rem" }}
              onClick={() => {
                setStep("phone");
                setCode("");
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
      </div>
    </div>
  );
}
