import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/status_bar.dart';

class HelpManualScreen extends StatelessWidget {
  final VoidCallback onBack;
  const HelpManualScreen({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          Container(
            width: double.infinity,
            color: AppColors.bleuFonce,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: onBack,
                  child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Aide / Manuel',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                const Text('📖', style: TextStyle(fontSize: 20)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _introCard(),
                const SizedBox(height: 12),
                _section(
                  icon: '🔐',
                  title: 'Connexion OTP',
                  children: const [
                    _P('SafeAlert utilise votre numéro de téléphone et un code à 6 chiffres envoyé par SMS.'),
                    _P('1. Saisissez votre numéro au format +243812345678 (ou 0812… — le +243 est ajouté automatiquement).'),
                    _P('2. Appuyez sur « Envoyer le code » et consultez le SMS reçu.'),
                    _P('3. Saisissez les 6 chiffres. Première utilisation : cochez « Nouveau compte » et choisissez un pseudo.'),
                    _P('En développement, le code peut s\'afficher dans l\'app (bandeau orange) si SMS non configuré.'),
                  ],
                ),
                _section(
                  icon: '🆘',
                  title: 'Bouton SOS',
                  children: const [
                    _P('Depuis l\'accueil, appuyez sur le bouton rouge SOS, puis confirmez sur l\'écran dédié.'),
                    _P('Votre position est envoyée et vos contacts de confiance sont alertés.'),
                    _P('Annulation : utilisez « Annuler l\'alerte » dans les 2 minutes suivant l\'envoi.'),
                    _P('SOS discret (Android) : 3× Volume bas avec l\'app ouverte pour déclencher sans afficher l\'écran SOS.'),
                  ],
                ),
                _section(
                  icon: '👥',
                  title: 'Contacts de confiance',
                  children: const [
                    _P('Onglet Confiance → « + Ajouter un contact » : nom et numéro du proche à alerter en cas de SOS.'),
                    _P('Ces personnes reçoivent une notification lorsque vous déclenchez une alerte.'),
                  ],
                ),
                _section(
                  icon: '🗺',
                  title: 'Carte des incidents',
                  children: const [
                    _P('Consultez les signalements autour de vous (marqueurs colorés).'),
                    _P('Filtrez par type et période (24h ou 7j). Touchez un marqueur pour les détails.'),
                    _P('Signalez un incident (bouton rouge) ou confirmez un signalement existant.'),
                  ],
                ),
                _section(
                  icon: '🏘',
                  title: 'Groupes voisins',
                  children: const [
                    _P('Créez un groupe ou rejoignez-en un avec un code d\'invitation.'),
                    _P('Rejoindre un groupe envoie une demande à l\'administrateur — vous n\'êtes pas ajouté immédiatement.'),
                    _P('Les créateurs et admins du groupe voient les demandes en attente et peuvent approuver ou refuser.'),
                  ],
                ),
                _section(
                  icon: '🕵️',
                  title: 'Mode discret',
                  children: const [
                    _P('Paramètres → « Camouflage calculatrice » : l\'app affiche une calculatrice.'),
                    _P('Saisissez le code de déverrouillage configuré pour retrouver SafeAlert.'),
                    _P('Sur iOS, la détection volume en arrière-plan est limitée.'),
                  ],
                ),
                _section(
                  icon: '👑',
                  title: 'Rôles dans l\'application',
                  children: const [
                    _P('Citoyen : SOS, contacts, carte, groupes, signalements.'),
                    _P('Responsable (leader) : en plus, Mode responsable pour gérer les incidents de son secteur.'),
                    _P('Agent : même accès responsable, filtré par secteur géographique assigné.'),
                    _P('Administrateur plateforme : gestion des utilisateurs, rôles et clés partenaires API.'),
                  ],
                ),
                _section(
                  icon: '🤝',
                  title: 'Partenaires ONG / autorités',
                  children: const [
                    _P('Les partenaires (ONG, autorités, intégrateurs) ne sont pas des utilisateurs mobiles.'),
                    _P('Ils accèdent à l\'API SafeAlert via une clé X-API-Key créée par un administrateur plateforme.'),
                    _P('Pas d\'écran mobile dédié : intégration serveur-à-serveur (incidents, statistiques, etc.).'),
                    _P('Un administrateur crée et révoque les clés dans Administration → Partenaires API.'),
                  ],
                ),
                _section(
                  icon: '⚙️',
                  title: 'Administration plateforme',
                  children: const [
                    _P('Réservé au rôle Administrateur plateforme (accueil ou Paramètres).'),
                    _P('Utilisateurs : changer le rôle, attribuer un secteur géographique.'),
                    _P('Partenaires API : créer une clé pour un organisme externe, révoquer une clé inactive.'),
                  ],
                ),
                _section(
                  icon: '🚦',
                  title: 'Zones Danger / Vigilance / Sûr',
                  children: const [
                    _P('Gravité (couleur du marqueur) ≠ statut (actif, vérifié, résolu…). La carte n\'affiche que les incidents encore ouverts.'),
                    _P('Alerte (rouge) : SOS déclenché — gravité initiale automatique.'),
                    _P('Vigilance (orange) : signalement carte (vol, agression…) — gravité initiale automatique.'),
                    _P('Danger (rouge) : 3 confirmations citoyennes ou plus sur un signalement ou un SOS.'),
                    _P('Sûr (vert) : un responsable résout l\'incident et il ne reste aucun autre incident actif dans le quartier (24 h).'),
                    _P('Qui change quoi : citoyen → SOS, signalement, confirmation ; responsable → prise en charge et résolution ; annulation SOS (2 min) → fausse alerte.'),
                    _P('Carte de chaleur : intensité = nombre total d\'incidents par quartier (30 j), pas la couleur d\'un marqueur.'),
                    _P('Le nom de quartier est déterminé automatiquement via GPS (OpenStreetMap).'),
                  ],
                ),
                _section(
                  icon: '🔔',
                  title: 'Notifications push (Firebase)',
                  children: const [
                    _P('Android : notifications configurées via Firebase (projet safealert-prod). Test possible depuis un PC Windows.'),
                    _P('iOS : nécessite d\'ajouter l\'app dans Firebase avec l\'identifiant com.safealert.safealert, puis le fichier GoogleService-Info.plist.'),
                    _P('Sous Windows, vous ne pouvez pas compiler ni tester sur iPhone — seul un Mac avec Xcode le permet. Préparez Firebase maintenant ; testez iOS plus tard.'),
                    _P('Push sur iPhone réel : une clé APNs (.p8) doit aussi être téléversée dans Firebase (Cloud Messaging).'),
                    _P('Guide détaillé : docs/FIREBASE_SETUP.md dans le dépôt du projet.'),
                  ],
                ),
                _section(
                  icon: '❓',
                  title: 'FAQ',
                  children: const [
                    _P('Code OTP non reçu ? Vérifiez le format +243…, attendez 1–2 min. Compte Twilio d\'essai : numéro vérifié requis.'),
                    _P('Serveur inaccessible ? En dev, utilisez l\'IP Wi-Fi du PC (pas localhost) sur le même réseau.'),
                    _P('Mode invité : carte et annuaire sans compte. Connexion requise pour SOS, contacts et signalements.'),
                    _P('Suppression de compte : Paramètres → Supprimer le compte (irréversible).'),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'SafeAlert — juin 2026',
                    style: TextStyle(fontSize: 10, color: AppColors.gris.withValues(alpha: 0.8)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _introCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.bleuFonce, AppColors.bleuFonce.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Manuel d\'utilisation',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
          SizedBox(height: 6),
          Text(
            'Guide rapide pour utiliser SafeAlert au quotidien. Touchez une section pour l\'ouvrir.',
            style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _section({required String icon, required String title, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.blanc,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Text(icon, style: const TextStyle(fontSize: 20)),
          title: Text(title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
          children: children,
        ),
      ),
    );
  }
}

class _P extends StatelessWidget {
  final String text;
  const _P(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.gris, height: 1.45)),
    );
  }
}
