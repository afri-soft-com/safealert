export default function ManuelPage() {
  return (
    <div className="legal-standalone">
      <header>
        <p className="legal-brand">SafeAlert — AfriSoft</p>
        <h1>Manuel utilisateur</h1>
        <p>Guide citoyen (application mobile) — 5 septembre 2026</p>
      </header>
      <article>
        <p>
          SafeAlert est l’application de sécurité citoyenne d’AfriSoft : alerte SOS, contacts de
          confiance, carte des incidents et entraide de quartier.
        </p>
        <h2>1. Connexion</h2>
        <ol>
          <li>Saisissez votre numéro (l’indicatif +243 est ajouté si besoin).</li>
          <li>Recevez le code SMS à 6 chiffres, puis créez un PIN local.</li>
          <li>Après déconnexion, entrez le PIN (pas de SMS). « Changer de numéro » recommence avec le téléphone.</li>
        </ol>
        <h2>2. Alerte SOS</h2>
        <ul>
          <li>Accueil → bouton rouge SOS → maintenir environ 2 secondes.</li>
          <li>Vos contacts de confiance sont alertés avec votre position.</li>
          <li>SOS discret (Android) : 3× volume bas, ou secouer le téléphone.</li>
        </ul>
        <h2>3. Autres fonctions</h2>
        <ul>
          <li>Contacts de confiance, carte, groupes voisins, trajet sécurisé.</li>
          <li>Une bannière de mise à jour peut apparaître pendant l’usage.</li>
        </ul>
        <p>
          Dans l’app : Accueil → <strong>Aide / Manuel</strong>, ou Paramètres → Aide.
        </p>
        <p className="legal-links">
          <a href="/cgu">CGU</a>
          {" · "}
          <a href="/manuel.html">Version HTML</a>
          {" · "}
          <a href="/aide">Aide console</a>
          {" · "}
          <a href="/connexion">Connexion admin</a>
        </p>
      </article>
    </div>
  );
}
