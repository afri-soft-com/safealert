import { useCallback, useEffect, useState, type ReactNode } from "react";
import { useLocation } from "react-router-dom";
import { api, isStaffRole } from "../api/client";
import { useAuth } from "../context/AuthContext";
import MaintenancePage from "../pages/MaintenancePage";

const POLL_MS = 10 * 60 * 1000;

const LEGAL_PATHS = new Set([
  "/connexion",
  "/portail-partenaire",
  "/cgu",
  "/manuel",
  "/cgu.html",
  "/manuel.html",
  "/privacy.html",
]);

export default function MaintenanceGate({ children }: { children: ReactNode }) {
  const { user, isAuthenticated, ready } = useAuth();
  const location = useLocation();
  const [maintenance, setMaintenance] = useState(false);
  const [message, setMessage] = useState("");
  const [cfgReady, setCfgReady] = useState(false);

  const refresh = useCallback(async () => {
    try {
      const cfg = await api.getAppConfig();
      setMaintenance(cfg.maintenance === true);
      setMessage(cfg.maintenanceBanner || "");
    } catch {
      /* offline — keep last known state */
    } finally {
      setCfgReady(true);
    }
  }, []);

  useEffect(() => {
    void refresh();
    const id = window.setInterval(() => void refresh(), POLL_MS);
    const onFocus = () => void refresh();
    const onVisibility = () => {
      if (document.visibilityState === "visible") void refresh();
    };
    window.addEventListener("focus", onFocus);
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      window.clearInterval(id);
      window.removeEventListener("focus", onFocus);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, [refresh, isAuthenticated, location.pathname]);

  if (!ready || !cfgReady) {
    return <div className="loading">Chargement…</div>;
  }

  const staff = isAuthenticated && isStaffRole(user?.role);
  if (maintenance && !staff && !LEGAL_PATHS.has(location.pathname)) {
    return <MaintenancePage message={message} />;
  }

  return <>{children}</>;
}
