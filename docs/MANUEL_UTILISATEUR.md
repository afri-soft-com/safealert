# Manuel d'utilisateur — SafeAlert

Guide pas à pas pour les citoyens utilisant l'application SafeAlert sur Android.

---

## 1. Installation de l'application

### Depuis le Play Store (recommandé)

1. Ouvrez le **Google Play Store** sur votre téléphone Android.
2. Recherchez **SafeAlert**.
3. Appuyez sur **Installer**, puis **Ouvrir**.

> [À capturer] Écran Play Store avec SafeAlert

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
4. Ces personnes sont notifiées lors d'une alerte.

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
| **Groupes voisins** | Créer ou rejoindre un groupe d'entraide par quartier |
| **Conseils sécurité** | Astuces disponibles hors ligne |
| **Carte chaleur** | Densité des incidents par zone |
| **Mon historique** | Vos alertes passées |
| **Mode responsable** | Réservé aux rôles leader/agent |

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

- Les données récentes (incidents, contacts, annuaire) sont **mises en cache**.
- Un bandeau indique **Mode hors-ligne** quand le serveur est inaccessible.
- Le bouton SOS tente d'envoyer l'alerte dès que le réseau revient.

---

## 5. FAQ

### Je ne reçois pas le code OTP

- Vérifiez le format du numéro (`+243…`).
- Attendez 1 à 2 minutes (réseau mobile lent).
- **Compte Twilio d'essai** : seuls les numéros **vérifiés** dans la console Twilio peuvent recevoir des SMS. Ajoutez votre numéro dans [console.twilio.com](https://console.twilio.com) → Verified Caller IDs.
- En développement local, le code peut s'afficher dans l'application (bandeau orange « Mode dev ») ou dans le terminal du serveur.

### « Numéro de téléphone invalide »

Utilisez un numéro congolais valide : `+243` + 9 chiffres (ex. `+243812345678`).

### L'application ne se connecte pas au serveur

| Contexte | URL API |
|----------|---------|
| **Production** | Serveur déployé (ex. `https://api.votredomaine.com`) |
| **Développement local** | Adresse IP de votre PC sur le réseau Wi-Fi (ex. `http://192.168.1.10:3000/api`) — pas `localhost` sur un téléphone physique |

Vérifiez que le téléphone et le PC sont sur le **même réseau Wi-Fi** et que le pare-feu autorise le port 3000.

### Puis-je utiliser SafeAlert sans compte ?

Oui, en **mode invité** : consultation de la carte et de l'annuaire. La connexion est requise pour SOS, contacts et signalements.

### Comment supprimer mon compte ?

Paramètres → **Supprimer le compte** → confirmer. Action **irréversible**.

### Le mode discret ne fonctionne pas sur iPhone

La détection des touches volume en arrière-plan est **limitée sur iOS**. Le SOS discret par volume est optimisé pour **Android**.

---

## 6. Support

Pour toute question technique liée à votre déploiement, contactez l'administrateur de votre instance SafeAlert ou consultez la [documentation vivante](DOCUMENTATION_VIVANTE.md) (équipe technique).

---

*Dernière mise à jour : juin 2026*
