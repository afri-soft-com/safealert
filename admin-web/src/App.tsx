import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { AuthProvider } from "./context/AuthContext";
import Layout from "./components/Layout";
import ProtectedRoute from "./components/ProtectedRoute";
import UpdateBanner from "./components/UpdateBanner";
import LoginPage from "./pages/LoginPage";
import DashboardPage from "./pages/DashboardPage";
import UsersPage from "./pages/UsersPage";
import SubscriptionsPage from "./pages/SubscriptionsPage";
import PartnersPage from "./pages/PartnersPage";
import EmergencyPage from "./pages/EmergencyPage";
import IncidentsPage from "./pages/IncidentsPage";
import GroupsPage from "./pages/GroupsPage";
import OpsPage from "./pages/OpsPage";
import PartnerPortalPage from "./pages/PartnerPortalPage";
import HelpPage from "./pages/HelpPage";
import AuditPage from "./pages/AuditPage";

export default function App() {
  return (
    <AuthProvider>
      <UpdateBanner />
      <BrowserRouter>
        <Routes>
          <Route path="/connexion" element={<LoginPage />} />
          {/* Portail partenaire : authentification par clé API, hors console admin */}
          <Route path="/portail-partenaire" element={<PartnerPortalPage />} />
          <Route element={<ProtectedRoute />}>
            <Route element={<Layout />}>
              <Route index element={<DashboardPage />} />
              <Route path="ops" element={<OpsPage />} />
              <Route path="utilisateurs" element={<UsersPage />} />
              <Route path="abonnements" element={<SubscriptionsPage />} />
              <Route path="partenaires" element={<PartnersPage />} />
              <Route path="annuaire" element={<EmergencyPage />} />
              <Route path="incidents" element={<IncidentsPage />} />
              <Route path="groupes" element={<GroupsPage />} />
              <Route path="audit" element={<AuditPage />} />
              <Route path="aide" element={<HelpPage />} />
            </Route>
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}
