export default function CguPage() {
  return (
    <div className="legal-standalone">
      <header>
        <p className="legal-brand">SafeAlert — AfriSoft</p>
        <h1>Conditions générales d’utilisation</h1>
        <p>Dernière mise à jour : 5 septembre 2026</p>
      </header>
      <article>
        <p>
          SafeAlert est un service de sécurité citoyenne édité par AfriSoft (afri-soft.com).
          Ces CGU s’appliquent à l’application mobile, à l’API et à la console d’administration.
        </p>
        <h2>1. Objet</h2>
        <p>
          SafeAlert permet d’envoyer des alertes SOS, d’informer des contacts de confiance et de
          consulter une carte communautaire des incidents. Ce n’est pas un service d’urgence officiel.
        </p>
        <h2>2. Compte</h2>
        <p>
          L’accès se fait par numéro de téléphone et code SMS, puis éventuellement un code PIN local.
          Vous êtes responsable de la confidentialité de votre appareil et de votre PIN.
        </p>
        <h2>3. Usage responsable</h2>
        <p>
          Utilisez SafeAlert pour des situations réelles. Les fausses alertes, le harcèlement et
          l’usurpation d’identité sont interdits.
        </p>
        <h2>4. Localisation</h2>
        <p>
          La position n’est transmise que lorsque vous déclenchez une alerte, un signalement, ou une
          fonction qui l’exige, et si vous l’avez autorisée.
        </p>
        <h2>5. Disponibilité</h2>
        <p>
          Le service est fourni « en l’état ». AfriSoft ne garantit pas une intervention physique.
        </p>
        <p className="legal-links">
          <a href="/manuel">Manuel utilisateur</a>
          {" · "}
          <a href="/cgu.html">Version HTML</a>
          {" · "}
          <a href="/privacy.html">Confidentialité</a>
          {" · "}
          <a href="/connexion">Connexion admin</a>
        </p>
      </article>
    </div>
  );
}
