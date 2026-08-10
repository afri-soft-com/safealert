import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { AuthProvider } from "./context/AuthContext";
import Layout from "./components/Layout";
import ProtectedRoute from "./components/ProtectedRoute";
import LoginPage from "./pages/LoginPage";
import DashboardPage from "./pages/DashboardPage";
import UsersPage from "./pages/UsersPage";
import PartnersPage from "./pages/PartnersPage";
import EmergencyPage from "./pages/EmergencyPage";
import IncidentsPage from "./pages/IncidentsPage";
import GroupsPage from "./pages/GroupsPage";
import OpsPage from "./pages/OpsPage";
import PartnerPortalPage from "./pages/PartnerPortalPage";

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/connexion" element={<LoginPage />} />
          <Route element={<ProtectedRoute />}>
            <Route element={<Layout />}>
              <Route index element={<DashboardPage />} />
              <Route path="ops" element={<OpsPage />} />
              <Route path="utilisateurs" element={<UsersPage />} />
              <Route path="partenaires" element={<PartnersPage />} />
              <Route path="portail-partenaire" element={<PartnerPortalPage />} />
              <Route path="annuaire" element={<EmergencyPage />} />
              <Route path="incidents" element={<IncidentsPage />} />
              <Route path="groupes" element={<GroupsPage />} />
            </Route>
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}
