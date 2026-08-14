# Manuel d'utilisateur — SafeAlert

Guide pas à pas pour les citoyens utilisant l'application SafeAlert sur Android.

---

## 1. Installation de l'application

### Depuis le Play Store (recommandé)

1. Ouvrez le **Google Play Store** sur votre téléphone Android.
2. Recherchez **SafeAlert**.
3. Appuyez sur **Installer**, puis **Ouvrir**.

> [À capturer] Écran Play Store avec SafeAlert

### Mises à jour

SafeAlert peut vous prévenir **pendant que vous utilisez l’app** lorsqu’une nouvelle version est disponible :

- Une bannière « **Nouvelle version disponible** » apparaît en haut de l’écran (vous pouvez continuer à utiliser l’app, puis appuyer sur **Mettre à jour**).
- Si une mise à jour est **obligatoire**, un message vous demande de mettre à jour avant de continuer.
- Sur Android (installation via Play), la mise à jour peut aussi se télécharger en arrière-plan ; un message propose ensuite de **redémarrer** pour l’appliquer.

Vérifiez aussi régulièrement le Play Store → SafeAlert → **Mettre à jour**.

### Installation manuelle (APK)

Si vous recevez un fichier `.apk` de votre organisation :

1. Autorisez l'installation depuis des sources inconnues (Paramètres → Sécurité).
2. Ouvrez le fichier APK téléchargé.
3. Confirmez l'installation.

---

## 2. Première connexion

SafeAlert utilise votre **numéro de téléphone** et un **code à 6 chiffres** (OTP) envoyé par SMS.

### Étape 1 — Saisir votre numéro

1. À l'ouverture, l'écran de connexion s'affiche.
2. Saisissez votre numéro au format international, par exemple :
   - `+243812345678`
   - ou `0812345678` (le `+243` est ajouté automatiquement pour la RDC)
3. Appuyez sur **Envoyer le code**.

> [À capturer] Écran de connexion avec champ téléphone

### Étape 2 — Vérifier le code OTP

1. Consultez le **SMS** reçu (ou le code affiché en mode développement).
2. Saisissez les **6 chiffres** du code.
3. Si c'est votre **première utilisation**, cochez **Nouveau compte** et choisissez un **pseudo**.
4. Appuyez sur **Vérifier**.

Vous arrivez sur l'**écran d'accueil**.

### Numéros acceptés

- Format international **E.164** : `+243` suivi de 9 chiffres (ex. `+243812345678`).
- Les numéros locaux commençant par `0` sont convertis automatiquement.

---

## 3. Fonctions principales

### 3.1 Bouton SOS (urgence)

1. Depuis l'accueil, appuyez sur le grand bouton rouge **🆘 BOUTON SOS**.
2. Sur l'écran SOS, appuyez sur le cercle central **APPUYER**.
3. L'application envoie votre position et alerte vos **contacts de confiance** et la communauté.
4. Pour **annuler** une alerte envoyée par erreur, utilisez **Annuler l'alerte**.

> [À capturer] Écran SOS avec les étapes de confirmation

**SOS discret (Android)** : avec l'application ouverte, appuyez **3 fois** sur le bouton **Volume bas** pour déclencher une alerte sans afficher l'écran SOS.

### 3.2 Cercle de confiance (contacts)

1. Onglet **Confiance** (barre du bas).
2. Appuyez sur **+ Ajouter un contact de confiance**.
3. Saisissez le **nom** et le **numéro** du proche à alerter en cas de SOS.
4. Ou **Inviter (QR)** : générez un code / QR à partager (WhatsApp ou lien). La personne ouvre le lien ou saisit le code via **Code reçu**.
5. Ces personnes sont notifiées lors d'une alerte.

> [À capturer] Liste des contacts de confiance

### 3.3 Carte des incidents

1. Onglet **Carte**.
2. Consultez les signalements autour de vous (marqueurs colorés).
3. Filtrez par **type** et période (**24h** ou **7j**).
4. Touchez un marqueur pour voir les détails.
5. **Signaler un incident** : bouton rouge en bas (connexion requise).
6. **Confirmer** un signalement existant pour aider la communauté.

> [À capturer] Carte avec marqueurs et légende

### 3.4 Annuaire d'urgence

1. Onglet **Urgences**.
2. Consultez les numéros utiles (police, pompiers, hôpital…).
3. Fonctionne **hors ligne** grâce au cache local.

### 3.5 Tableau de bord (statistiques)

1. Onglet **Stats**.
2. Visualisez les incidents de votre quartier, les alertes SOS et les heures à risque.

### 3.6 Mode discret (calculatrice)

Pour masquer l'application derrière une calculatrice :

1. Menu ☰ → **Paramètres**.
2. Activez **Camouflage calculatrice** (Mode discret).
3. L'application affiche une calculatrice. Saisissez le code de déverrouillage configuré pour retrouver SafeAlert.

> [À capturer] Écran calculatrice (mode discret)

### 3.7 Autres fonctions (menu accueil)

| Fonction | Description |
|----------|-------------|
| **Groupes voisins** | Créer un groupe ou rejoindre via code / QR ; alertes structurées (électricité, eau, inondation, rue bloquée) |
| **Trajet sécurisé** | Partagez un lien « suivez mon trajet » (page web temporaire) + WhatsApp |
| **Contrôle « Tu es OK ? »** | Rappel planifié ; silence → proches prévenus (Paramètres) |
| **Envois en attente** | Voir et renvoyer SOS / signalements hors ligne (Paramètres) |
| **Aide / Manuel** | Guide intégré (connexion, SOS, rôles, FAQ) depuis l'accueil ou Paramètres |
| **Conseils sécurité** | Astuces disponibles hors ligne |
| **Carte chaleur** | Densité des incidents par zone et créneau (matin / soir / week-end) |
| **Mon historique** | Vos alertes passées |
| **Mode responsable** | Réservé aux rôles leader/agent (filtré par secteur si assigné) ; ETA visible par le citoyen |
| **Administration** | Réservé au rôle `platform_admin` (utilisateurs, rôles, partenaires API) |

### 3.10 Administration (administrateurs plateforme)

Réservé aux comptes avec le rôle **Administrateur plateforme** :

1. Depuis l'**accueil**, carte **Administration**, ou **Paramètres → Administration plateforme**.
2. Onglet **Utilisateurs** : liste paginée, changement de rôle (citoyen, responsable, agent, administrateur), attribution d'un **secteur géographique** (ex. Gombe, Limete).
3. Onglet **Partenaires API** : créer une clé pour un organisme externe, révoquer une clé inactive.

### 3.12 Rôles application vs partenaires API

| Type | Accès |
|------|--------|
| **Citoyen** | Application mobile standard (SOS, carte, groupes…) |
| **Responsable / Agent** | + Mode responsable (incidents du secteur assigné) |
| **Administrateur plateforme** | + Administration (utilisateurs, rôles, clés partenaires) |
| **Partenaire ONG / autorité** | **Pas d'application mobile** — intégration API avec en-tête `X-API-Key` |

Les partenaires sont des organismes externes (ONG, services publics, intégrateurs) qui consomment l'API SafeAlert côté serveur. Un administrateur plateforme crée leur clé dans **Administration → Partenaires API**. Ils n'ont pas de compte OTP ni d'écran dédié dans l'app.

### 3.13 À quoi servent les groupes voisins ?

Les **groupes voisins** permettent de créer une petite communauté d'entraide autour de votre quartier, immeuble ou rue. C'est un espace pour rester en contact avec des personnes proches géographiquement, partager des alertes locales et se soutenir mutuellement — par exemple en cas de coupure de courant, d'inondation ou de situation suspecte dans le voisinage.

Ils ne remplacent **pas** le **cercle de confiance** : vos contacts de confiance sont les proches (famille, amis) alertés automatiquement par **SMS et push** lors d'un **SOS**. Les groupes voisins reçoivent une **notification push** supplémentaire si vous activez **« Alerter mes groupes en SOS »** dans les paramètres (activé par défaut). Les groupes voisins ne servent **pas** à valider ou confirmer les incidents sur la carte — cette fonction reste ouverte à toute la communauté SafeAlert.

- **Créer un groupe** : vous devenez administrateur et recevez un **code d'invitation** à partager (SMS, WhatsApp, etc.).
- **Rejoindre un groupe** : saisissez le code **ou** demandez à rejoindre depuis **Groupes à découvrir** (groupes publics).
- **Gérer les adhésions** : l'administrateur approuve ou refuse les demandes en attente.
- **Une fois membre** : consultez la **liste des membres**, échangez par **messages** et publiez des **alertes locales** (info, aide, danger, coupure d'électricité/eau, inondation, rue bloquée).

### 3.14 Groupes voisins — étapes pratiques

1. Depuis l'accueil, ouvrez **Groupes voisins**.
2. **Créer** un groupe : choisissez un nom, partagez le code d'invitation.
3. **Rejoindre** : avec un code d'invitation **ou** bouton **Demander à rejoindre** sur un groupe découvrable.
4. L'**administrateur** approuve ou refuse les demandes depuis l'onglet **Membres** du groupe.
5. **Ouvrir** un groupe : onglets **Membres**, **Messages** (chat de groupe) et **Alertes** (entraide locale).
6. Publiez une **alerte locale** (coupure, inondation, aide…) via le bouton **Alerte** ; les membres sont notifiés par push.
7. En cas de **SOS**, vos groupes peuvent être alertés si l'option est activée dans **Paramètres → Confidentialité**.

Les responsables (leader/agent) avec un secteur assigné ne voient que les incidents dont la zone correspond à ce secteur dans **Mode responsable**.

### 3.11 Zones Danger / Vigilance / Sûr

Les incidents sont classés par **gravité** (`severity`) selon leur type et les confirmations communautaires :

| Niveau | Couleur CDC | Quand |
|--------|-------------|-------|
| **Alerte** (`alert`) | Rouge vif | SOS déclenché — urgence immédiate |
| **Vigilance** (`vigilance`) | Orange | Signalement communautaire (vol, agression, etc.) |
| **Danger** (`danger`) | Rouge confirmé | **3 confirmations** ou plus par la communauté |
| **Sûr** (`safe`) | Vert | Zone sans incident actif récent après résolution par un responsable |

Le **nom de zone** (`zone_name`) est déterminé automatiquement à partir du GPS (quartier / ville via OpenStreetMap). Il alimente la carte chaleur et le filtrage secteur des responsables.

### 3.8 Profil et paramètres

1. Menu ☰ (coin supérieur droit de l'accueil).
2. **Paramètres** : pseudo, téléphone, confidentialité, déconnexion, suppression de compte.

### 3.9 Navigation et retour arrière

- Sur les **écrans secondaires** (SOS, groupes, historique, paramètres, etc.), utilisez la **flèche ←** en haut à gauche pour revenir à l'écran précédent.
- Sur les **onglets principaux** (Carte, Confiance, Urgences, Stats), le bouton **Retour** du téléphone Android ramène à l'**Accueil**.
- Depuis l'**Accueil**, le bouton Retour Android **quitte l'application**.
- Dans **Paramètres → Politique de confidentialité**, la flèche ← ou le bouton Retour ramène aux paramètres.

---

## 4. Mode hors ligne

SafeAlert fonctionne avec une **connexion limitée** :

| Donnée | Cache local | Durée | Indicateur |
|--------|-------------|-------|------------|
| **Annuaire d'urgence** | SQLite | 24 h | Bandeau jaune « Mode hors-ligne » |
| **Carte (incidents)** | SQLite | 5 min | Icône 📶 sur la carte |
| **Contacts de confiance** | SQLite | 1 h | Bandeau jaune |
| **Conseils sécurité** | Intégrés à l'app | Permanent | Toujours disponible |

- L'annuaire et la carte affichent les **dernières données synchronisées** si le serveur est inaccessible (délai max. ~10 s).
- Un bandeau **Mode hors-ligne** indique que vous consultez le cache local.
- Le **bouton SOS** nécessite une connexion : un message d'erreur s'affiche si l'envoi échoue — réessayez lorsque le réseau est rétabli.
- **Mode invité** : annuaire et carte accessibles sans compte ; le cache s'applique de la même façon.

---

## 5. FAQ

### Je ne reçois pas le code OTP

- Vérifiez le format du numéro (`+243…`).
- Attendez 1 à 2 minutes, puis redemandez un code.
- Vérifiez que le SMS n'est pas bloqué par votre opérateur.
- Si le problème continue, contactez le support de votre organisation.

### « Numéro de téléphone invalide »

Utilisez un numéro congolais valide : `+243` + 9 chiffres (ex. `+243812345678`).

### L'application ne se connecte pas au serveur

- Vérifiez votre connexion Internet (Wi‑Fi ou données mobiles).
- Fermez puis rouvrez l'application.
- Si le message persiste, contactez le support de votre organisation.

### Comment devenir administrateur ou responsable ?

Les rôles (**responsable**, **agent**, **administrateur**) sont attribués par l'**administrateur plateforme** de votre organisation (console admin → Utilisateurs). Contactez-le si vous avez besoin d'un accès étendu.

### Puis-je utiliser SafeAlert sans compte ?

Oui, en **mode invité** : consultation de la carte et de l'annuaire. La connexion est requise pour SOS, contacts et signalements.

### Comment supprimer mon compte ?

Paramètres → **Supprimer le compte** → confirmer. Action **irréversible**.

### Le mode discret ne fonctionne pas sur iPhone

La détection des touches volume en arrière-plan est **limitée sur iOS**. Le SOS discret par volume est optimisé pour **Android**.

---

## 6. Console d'administration (web)

Réservée aux **administrateurs plateforme**. Connexion par téléphone + code SMS.

- Tableau de bord, ops temps réel, utilisateurs, partenaires, annuaire, incidents, groupes.
- **Portail partenaire** : page séparée (`/portail-partenaire`) pour les organisations avec clé API.
- Aide intégrée : menu **Aide** dans la console.
- Détails techniques : [ADMIN_WEB.md](ADMIN_WEB.md).

## 7. Support

Pour toute question, contactez l'administrateur de votre instance SafeAlert.

Dans l'application : **Accueil → Aide / Manuel** ou **Paramètres → Aide**.

---

*Dernière mise à jour : août 2026*
