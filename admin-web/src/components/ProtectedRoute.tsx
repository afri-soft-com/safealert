import { Navigate, Outlet } from "react-router-dom";
import { isStaffRole } from "../api/client";
import { useAuth } from "../context/AuthContext";

export default function ProtectedRoute() {
  const { canEnterConsole, user, ready } = useAuth();

  if (!ready) {
    return <div className="loading">Vérification de la session…</div>;
  }

  if (!canEnterConsole || !isStaffRole(user?.role)) {
    return <Navigate to="/connexion" replace />;
  }

  return <Outlet />;
}
