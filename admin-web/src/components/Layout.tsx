import { NavLink, Outlet } from "react-router-dom";
import { useAuth } from "../context/AuthContext";

/** Navigation console — réservée aux platform_admin (garde ProtectedRoute). */
const NAV = [
  { to: "/", label: "Tableau de bord", end: true },
  { to: "/ops", label: "Ops temps réel" },
  { to: "/utilisateurs", label: "Utilisateurs" },
  { to: "/partenaires", label: "Partenaires API" },
  { to: "/annuaire", label: "Annuaire d'urgence" },
  { to: "/incidents", label: "Incidents" },
  { to: "/groupes", label: "Groupes" },
  { to: "/audit", label: "Journal d'audit" },
  { to: "/aide", label: "Aide" },
];

export default function Layout() {
  const { user, logout } = useAuth();

  return (
    <div className="app-layout">
      <aside className="sidebar">
        <div className="sidebar-brand">
          <h1>SafeAlert</h1>
          <p>Console d'administration</p>
        </div>
        <nav className="sidebar-nav">
          {NAV.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              className={({ isActive }) => `nav-link${isActive ? " active" : ""}`}
            >
              {item.label}
            </NavLink>
          ))}
        </nav>
        <div className="sidebar-footer">
          <div>{user?.pseudo}</div>
          <div>{user?.phone}</div>
          <a
            href="/portail-partenaire"
            target="_blank"
            rel="noreferrer"
            style={{ fontSize: 12, display: "block", marginBottom: 8 }}
          >
            Portail partenaire ↗
          </a>
          <button type="button" onClick={logout}>
            Déconnexion
          </button>
        </div>
      </aside>
      <main className="main-content">
        <Outlet />
      </main>
    </div>
  );
}
