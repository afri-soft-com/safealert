/** Fallback privacy policy when app_settings LEGAL_PRIVACY_* are empty. */
const DEFAULT_PRIVACY_TITLE = "Politique de confidentialité — SafeAlert";
const DEFAULT_PRIVACY_VERSION = "1.0";
const DEFAULT_PRIVACY_BODY = `# Politique de confidentialité — SafeAlert

**Dernière mise à jour :** août 2026  
**Application :** SafeAlert — sécurité citoyenne (mobile, API, console d'administration)

## 1. Responsable du traitement

SafeAlert est opéré par l'éditeur de l'application. Pour toute question relative à vos données : contactez le support via le compte développeur Play Console / App Store ou l'adresse indiquée dans la fiche store.

## 2. Données collectées

- **Compte :** numéro de téléphone, pseudo, rôle (citoyen, leader, etc.), e-mail / identifiants Google ou Apple le cas échéant.
- **Authentification :** codes OTP envoyés par SMS (stockés de façon hashée, durée limitée).
- **Localisation :** position GPS lors d'un SOS, d'un signalement ou de la mise à jour de présence (avec votre autorisation).
- **Contenu d'urgence :** incidents SOS, descriptions, contacts de confiance, groupes de voisins.
- **Notifications :** jeton Firebase Cloud Messaging (FCM) pour les alertes push.
- **Données techniques :** journaux serveur nécessaires au fonctionnement et à la sécurité (ex. adresse IP pour le rate-limiting).

## 3. Finalités

- Créer et sécuriser votre compte (OTP / Google / Apple).
- Déclencher et diffuser des alertes SOS aux contacts / communauté.
- Afficher la carte des incidents et l'annuaire d'urgence.
- Améliorer la fiabilité, la sécurité et la prévention des abus.
- Administrer la plateforme (comptes platform_admin uniquement).

## 4. Base légale

Traitement fondé sur votre consentement (localisation, notifications), l'exécution du service que vous demandez (SOS, compte) et l'intérêt légitime de sécuriser la plateforme.

## 5. Partage des données

- Vos alertes peuvent être visibles par vos contacts de confiance, membres de groupes concernés, et opérateurs autorisés.
- Prestataires techniques : hébergement, base de données, SMS (ex. hub AfriSoft / SerdiPay), Firebase (notifications).
- Nous ne vendons pas vos données personnelles.

## 6. Conservation

Les codes OTP expirent rapidement. Les comptes et incidents sont conservés tant que le service est utilisé, ou jusqu'à suppression de compte / demande d'effacement, sous réserve d'obligations légales.

## 7. Sécurité

Communications HTTPS, OTP hashés, contrôle d'accès par rôles, journalisation d'administration. Aucune mesure n'étant absolue, signalez tout incident de sécurité au support.

## 8. Vos droits

Selon la législation applicable, vous pouvez demander l'accès, la rectification, la suppression de votre compte (fonction prévue dans l'app) ou vous opposer à certains traitements (ex. désactiver la localisation ou les notifications dans les paramètres du téléphone).

## 9. Données des mineurs

SafeAlert n'est pas destiné aux enfants. Si vous pensez qu'un mineur a fourni des données, contactez-nous pour suppression.

## 10. Modifications

Cette politique peut être mise à jour. La version et la date seront révisées ; l'usage continu du service après publication vaut prise de connaissance des changements matériels.

## 11. Contact

Pour exercer vos droits ou poser une question : utilisez le canal de contact de la fiche store « SafeAlert » ou le support indiqué par l'éditeur.
`;

module.exports = {
  DEFAULT_PRIVACY_TITLE,
  DEFAULT_PRIVACY_VERSION,
  DEFAULT_PRIVACY_BODY,
};
