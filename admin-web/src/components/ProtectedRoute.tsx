import { Navigate, Outlet } from "react-router-dom";
import { useAuth } from "../context/AuthContext";

export default function ProtectedRoute() {
  const { isAuthenticated, user, ready } = useAuth();

  if (!ready) {
    return <div className="loading">Vérification de la session…</div>;
  }

  if (!isAuthenticated || user?.role !== "platform_admin") {
    return <Navigate to="/connexion" replace />;
  }

  return <Outlet />;
}
