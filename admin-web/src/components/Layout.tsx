import { NavLink, Outlet } from "react-router-dom";
import { useAuth } from "../context/AuthContext";

const NAV = [
  { to: "/", label: "Tableau de bord", icon: "📊" },
  { to: "/utilisateurs", label: "Utilisateurs", icon: "👥" },
  { to: "/partenaires", label: "Partenaires API", icon: "🔑" },
  { to: "/annuaire", label: "Annuaire d'urgence", icon: "📞" },
  { to: "/incidents", label: "Incidents", icon: "🚨" },
  { to: "/groupes", label: "Groupes", icon: "🏘️" },
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
              end={item.to === "/"}
              className={({ isActive }) => `nav-link${isActive ? " active" : ""}`}
            >
              <span>{item.icon}</span>
              {item.label}
            </NavLink>
          ))}
        </nav>
        <div className="sidebar-footer">
          <div>{user?.pseudo}</div>
          <div>{user?.phone}</div>
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
