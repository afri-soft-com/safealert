import { Link } from "react-router-dom";

export default function MaintenancePage({
  message,
}: {
  message?: string;
}) {
  return (
    <div className="maintenance-page">
      <div className="maintenance-inner">
        <h1>Maintenance en cours</h1>
        <p className="maintenance-lead">
          {message ||
            "Nous effectuons une mise à jour de la plateforme. Le service sera de retour très bientôt."}
        </p>
        <div className="maintenance-box">
          Merci de votre patience · Équipe SafeAlert
        </div>
      </div>
      <Link to="/connexion" className="maintenance-admin-link">
        Connexion super administrateur →
      </Link>
    </div>
  );
}
