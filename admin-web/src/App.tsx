import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { AuthProvider } from "./context/AuthContext";
import Layout from "./components/Layout";
import ProtectedRoute from "./components/ProtectedRoute";
import MaintenanceGate from "./components/MaintenanceGate";
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
import SettingsPage from "./pages/SettingsPage";
import CguPage from "./pages/CguPage";
import ManuelPage from "./pages/ManuelPage";

export default function App() {
  return (
    <AuthProvider>
      <UpdateBanner />
      <BrowserRouter>
        <MaintenanceGate>
          <Routes>
            <Route path="/cgu" element={<CguPage />} />
            <Route path="/manuel" element={<ManuelPage />} />
            <Route path="/connexion" element={<LoginPage />} />
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
                <Route path="reglages" element={<SettingsPage />} />
                <Route path="aide" element={<HelpPage />} />
              </Route>
            </Route>
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </MaintenanceGate>
      </BrowserRouter>
    </AuthProvider>
  );
}
