import { NavLink, Outlet } from "react-router-dom";
import { isSuperAdmin, ROLE_LABELS } from "../api/client";
import { useAuth } from "../context/AuthContext";

const NAV = [
  { to: "/", label: "Tableau de bord", end: true },
  { to: "/ops", label: "Ops temps réel" },
  { to: "/utilisateurs", label: "Utilisateurs" },
  { to: "/abonnements", label: "Abonnements" },
  { to: "/partenaires", label: "Partenaires API" },
  { to: "/annuaire", label: "Annuaire d'urgence" },
  { to: "/incidents", label: "Incidents" },
  { to: "/groupes", label: "Groupes" },
  { to: "/audit", label: "Journal d'audit" },
  { to: "/aide", label: "Aide" },
];

export default function Layout() {
  const { user, logout } = useAuth();
  const superAdmin = isSuperAdmin(user?.role);
  const items = superAdmin
    ? [...NAV, { to: "/reglages", label: "Réglages" }]
    : NAV;

  return (
    <div className="app-layout">
      <aside className="sidebar">
        <div className="sidebar-brand">
          <h1>SafeAlert</h1>
          <p>Console d'administration</p>
        </div>
        <nav className="sidebar-nav">
          {items.map((item) => (
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
          <div style={{ fontSize: 12, opacity: 0.8, marginBottom: 8 }}>
            {user?.role ? ROLE_LABELS[user.role] : ""}
          </div>
          <a
            href="/portail-partenaire"
            target="_blank"
            rel="noreferrer"
            style={{ fontSize: 12, display: "block", marginBottom: 8 }}
          >
            Portail partenaire ↗
          </a>
          <a href="/manuel.html" style={{ fontSize: 12, display: "block", marginBottom: 4 }}>
            Manuel utilisateur
          </a>
          <a href="/cgu.html" style={{ fontSize: 12, display: "block", marginBottom: 8 }}>
            CGU
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
