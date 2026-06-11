import { FormEvent, useState } from "react";
import { Navigate } from "react-router-dom";
import { api, ApiError } from "../api/client";
import { useAuth } from "../context/AuthContext";

export default function LoginPage() {
  const { isAuthenticated, login } = useAuth();
  const [phone, setPhone] = useState("+243");
  const [code, setCode] = useState("");
  const [step, setStep] = useState<"phone" | "code">("phone");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [devHint, setDevHint] = useState("");

  if (isAuthenticated) return <Navigate to="/" replace />;

  const handleRequestCode = async (e: FormEvent) => {
    e.preventDefault();
    setError("");
    setDevHint("");
    setLoading(true);
    try {
      const res = await api.requestCode(phone.trim());
      if (res.devCode) {
        setDevHint(`Mode dev — code OTP : ${res.devCode}`);
        setCode(res.devCode);
      }
      setStep("code");
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Impossible d'envoyer le code");
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
      setError(err instanceof Error ? err.message : "Connexion impossible");
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
              {loading ? "Envoi…" : "Recevoir le code OTP"}
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
          En développement sans SMS, le code OTP s'affiche dans le terminal backend{" "}
          <code>[DEV OTP]</code>.
        </p>
      </div>
    </div>
  );
}
