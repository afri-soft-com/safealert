import { useEffect, useState } from "react";
import { api } from "../api/client";

export default function DashboardPage() {
  const [stats, setStats] = useState<{
    users: number;
    incidents: number;
    active_incidents: number;
    active_partners: number;
    groups: number;
  } | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    api
      .getStats()
      .then(setStats)
      .catch(() => setError("Impossible de charger les statistiques"));
  }, []);

  return (
    <>
      <header className="page-header">
        <h2>Tableau de bord</h2>
        <p>Vue d'ensemble de la plateforme SafeAlert</p>
      </header>

      {error && <div className="form-error">{error}</div>}

      {!stats && !error ? (
        <div className="loading">Chargement…</div>
      ) : stats ? (
        <div className="stats-grid">
          <div className="stat-card accent">
            <div className="label">Utilisateurs</div>
            <div className="value">{stats.users}</div>
          </div>
          <div className="stat-card">
            <div className="label">Incidents totaux</div>
            <div className="value">{stats.incidents}</div>
          </div>
          <div className="stat-card accent">
            <div className="label">Incidents actifs</div>
            <div className="value">{stats.active_incidents}</div>
          </div>
          <div className="stat-card">
            <div className="label">Partenaires actifs</div>
            <div className="value">{stats.active_partners}</div>
          </div>
          <div className="stat-card">
            <div className="label">Groupes voisins</div>
            <div className="value">{stats.groups}</div>
          </div>
        </div>
      ) : null}
    </>
  );
}
