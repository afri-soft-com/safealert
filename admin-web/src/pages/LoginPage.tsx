import { FormEvent, useEffect, useState } from "react";
import { Navigate } from "react-router-dom";
import { ApiError, api } from "../api/client";
import { useAuth } from "../context/AuthContext";
import { userFacingError } from "../utils/userFacingError";

function needsPseudo(err: unknown): boolean {
  if (!(err instanceof ApiError) && !(err instanceof Error)) return false;
  return /pseudo\s+requis/i.test(err.message) || /aucun compte pour ce num[eé]ro/i.test(err.message);
}

function maskedPhone(phone: string | null | undefined): string {
  if (!phone || phone.length < 4) return "";
  return `•••• ${phone.slice(-4)}`;
}

type Step = "phone" | "code" | "pinUnlock" | "pinCreate";

export default function LoginPage() {
  const {
    isAuthenticated,
    ready,
    login,
    hasLocalPin,
    needsPinSetup,
    pinPhone,
    user,
    setLocalPin,
    unlockWithPin,
    requestForgotPinCode,
    switchPhone,
  } = useAuth();
  const [phone, setPhone] = useState("+243");
  const [code, setCode] = useState("");
  const [pseudo, setPseudo] = useState("");
  const [needPseudo, setNeedPseudo] = useState(false);
  const [pin, setPin] = useState("");
  const [pinConfirm, setPinConfirm] = useState("");
  const [step, setStep] = useState<Step>("phone");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [devHint, setDevHint] = useState("");

  useEffect(() => {
    if (!ready) return;
    if (needsPinSetup && user) {
      setStep("pinCreate");
    } else if (hasLocalPin) {
      setStep("pinUnlock");
    }
  }, [ready, needsPinSetup, user, hasLocalPin]);

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
      setPin("");
      setPinConfirm("");
      setStep("pinCreate");
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

  const handleUnlock = async (e: FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      const ok = await unlockWithPin(pin.trim());
      if (!ok) {
        setError("Code PIN incorrect, ou session expirée. Utilisez « Code PIN oublié ».");
      }
    } catch (err) {
      setError(userFacingError(err, "Impossible de vérifier le code PIN."));
    } finally {
      setLoading(false);
    }
  };

  const handleCreatePin = async (e: FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await setLocalPin(pin.trim(), pinConfirm.trim());
    } catch (err) {
      setError(userFacingError(err, "Impossible d'enregistrer le code PIN."));
    } finally {
      setLoading(false);
    }
  };

  const handleForgotPin = async () => {
    setError("");
    setDevHint("");
    setLoading(true);
    try {
      const res = await requestForgotPinCode();
      const stored = pinPhone || user?.phone;
      if (stored) setPhone(stored);
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

  const handleSwitchPhone = () => {
    switchPhone();
    setPhone("+243");
    setCode("");
    setPin("");
    setPinConfirm("");
    setNeedPseudo(false);
    setDevHint("");
    setError("");
    setStep("phone");
  };

  const subtitle =
    step === "pinUnlock"
      ? "Entrez votre code PIN pour ouvrir la console"
      : step === "pinCreate"
        ? "Créez un code PIN (4 à 6 chiffres). Plus de SMS à chaque connexion."
        : step === "code"
          ? "Saisissez le code reçu par SMS"
          : "Connexion réservée aux administrateurs";

  const displayPhone = maskedPhone(pinPhone || user?.phone);

  return (
    <div className="login-page">
      <div className="login-card">
        <h1>SafeAlert Admin</h1>
        <p className="subtitle">{subtitle}</p>

        {error && <div className="form-error">{error}</div>}

        {step === "phone" && (
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
        )}

        {step === "code" && (
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
              onClick={handleSwitchPhone}
            >
              Changer de numéro
            </button>
          </form>
        )}

        {step === "pinUnlock" && (
          <form onSubmit={handleUnlock}>
            {displayPhone && <p className="form-hint">Numéro {displayPhone}</p>}
            <div className="form-group">
              <label htmlFor="pin">Code PIN</label>
              <input
                id="pin"
                type="password"
                inputMode="numeric"
                autoComplete="off"
                maxLength={6}
                value={pin}
                onChange={(e) => setPin(e.target.value.replace(/\D/g, ""))}
                required
              />
            </div>
            <button type="submit" className="btn btn-primary" style={{ width: "100%" }} disabled={loading}>
              {loading ? "Vérification…" : "Déverrouiller"}
            </button>
            <button
              type="button"
              className="btn btn-secondary"
              style={{ width: "100%", marginTop: "0.5rem" }}
              onClick={handleForgotPin}
              disabled={loading}
            >
              Code PIN oublié
            </button>
            <button
              type="button"
              className="btn btn-secondary"
              style={{ width: "100%", marginTop: "0.5rem" }}
              onClick={handleSwitchPhone}
              disabled={loading}
            >
              Changer de numéro
            </button>
          </form>
        )}

        {step === "pinCreate" && (
          <form onSubmit={handleCreatePin}>
            <div className="form-group">
              <label htmlFor="pin-new">PIN (6 chiffres recommandés)</label>
              <input
                id="pin-new"
                type="password"
                inputMode="numeric"
                autoComplete="off"
                maxLength={6}
                value={pin}
                onChange={(e) => setPin(e.target.value.replace(/\D/g, ""))}
                required
              />
            </div>
            <div className="form-group">
              <label htmlFor="pin-confirm">Confirmez le code PIN</label>
              <input
                id="pin-confirm"
                type="password"
                inputMode="numeric"
                autoComplete="off"
                maxLength={6}
                value={pinConfirm}
                onChange={(e) => setPinConfirm(e.target.value.replace(/\D/g, ""))}
                required
              />
            </div>
            <button type="submit" className="btn btn-primary" style={{ width: "100%" }} disabled={loading}>
              {loading ? "Enregistrement…" : "Enregistrer le PIN"}
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
