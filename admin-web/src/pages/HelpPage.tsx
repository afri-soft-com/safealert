export default function HelpPage() {
  return (
    <>
      <header className="page-header">
        <h2>Aide — console d&apos;administration</h2>
        <p>Guide pratique pour les administrateurs plateforme SafeAlert</p>
      </header>

      <div className="card">
        <h3>Rôles</h3>
        <ul>
          <li>
            <strong>Citoyen</strong> — application mobile (SOS, contacts, carte, groupes).
          </li>
          <li>
            <strong>Responsable / Agent</strong> — Mode responsable dans l&apos;app (incidents du
            secteur). Pas d&apos;accès à cette console web.
          </li>
          <li>
            <strong>Administrateur plateforme</strong> — cette console : utilisateurs, partenaires,
            ops, annuaire, incidents, groupes.
          </li>
        </ul>

        <h3 style={{ marginTop: 20 }}>Pages principales</h3>
        <ul>
          <li>
            <strong>Ops temps réel</strong> — file SOS, délais de prise en charge, export CSV/PDF.
          </li>
          <li>
            <strong>Utilisateurs</strong> — recherche, attribution de rôle / secteur.
          </li>
          <li>
            <strong>Abonnements</strong> — CRUD Premium (accorder, prolonger, révoquer), stats MRR,
            offre 2 USD / mois.
          </li>
          <li>
            <strong>Partenaires API</strong> — création / révocation de clés API.
          </li>
          <li>
            <strong>Portail partenaire</strong> — espace séparé (lien en bas du menu) pour les
            organisations partenaires avec leur clé API.
          </li>
          <li>
            <strong>Incidents</strong> — consultation et détail (description, zone / lieu,
            coordonnées GPS, signaleur).
          </li>
        </ul>

        <h3 style={{ marginTop: 20 }}>Documentation complète</h3>
        <p>
          <a href="/manuel.html">Manuel utilisateur (citoyens)</a>
          {" — "}
          aussi dans l&apos;application : Accueil → <strong>Aide / Manuel</strong> ou Paramètres → Aide.
        </p>
        <p>
          <a href="/cgu.html">Conditions générales d&apos;utilisation</a>
          {" · "}
          <a href="/privacy.html">Politique de confidentialité</a>
        </p>
        <p>
          Guide console admin : <code>docs/ADMIN_WEB.md</code>.
        </p>
      </div>
    </>
  );
}
