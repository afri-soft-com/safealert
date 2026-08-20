import { useEffect, useState, type ReactNode } from "react";
import { useLocation } from "react-router-dom";
import { api, isStaffRole } from "../api/client";
import { useAuth } from "../context/AuthContext";
import MaintenancePage from "../pages/MaintenancePage";

export default function MaintenanceGate({ children }: { children: ReactNode }) {
  const { user, isAuthenticated, ready } = useAuth();
  const location = useLocation();
  const [maintenance, setMaintenance] = useState(false);
  const [message, setMessage] = useState("");
  const [cfgReady, setCfgReady] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const cfg = await api.getAppConfig();
        if (cancelled) return;
        setMaintenance(cfg.maintenance === true);
        setMessage(cfg.maintenanceBanner || "");
      } catch {
        if (!cancelled) setMaintenance(false);
      } finally {
        if (!cancelled) setCfgReady(true);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [isAuthenticated, location.pathname]);

  if (!ready || !cfgReady) {
    return <div className="loading">Chargement…</div>;
  }

  const staff = isAuthenticated && isStaffRole(user?.role);
  const openPaths =
    location.pathname === "/connexion" || location.pathname === "/portail-partenaire";

  if (maintenance && !staff && !openPaths) {
    return <MaintenancePage message={message} />;
  }

  return <>{children}</>;
}
