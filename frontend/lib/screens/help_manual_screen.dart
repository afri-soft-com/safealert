import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../widgets/status_bar.dart';

const _kHostedManualUrl = 'https://safealert-admin.onrender.com/manuel.html';

/// Manuel d'utilisation filtré selon le rôle plateforme.
class HelpManualScreen extends StatelessWidget {
  final VoidCallback onBack;
  final String role;
  const HelpManualScreen({
    super.key,
    required this.onBack,
    this.role = UserRoles.citizen,
  });

  bool get _isOps =>
      role == UserRoles.leader ||
      role == UserRoles.agent ||
      role == UserRoles.admin ||
      role == UserRoles.platformAdmin;
  bool get _isAdmin =>
      role == UserRoles.admin || role == UserRoles.platformAdmin;

  @override
  Widget build(BuildContext context) {
    final roleLabel = UserRoles.labels[role] ?? 'Citoyen';

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
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _introCard(roleLabel),
                const SizedBox(height: 12),
                _section(
                  icon: Icons.phone_android,
                  title: 'Connexion',
                  children: const [
                    _P('SafeAlert utilise votre numéro de téléphone et un code à 6 chiffres envoyé par SMS.'),
                    _P('1. Saisissez votre numéro (ex. 0812… — l\'indicatif +243 est ajouté si besoin).'),
                    _P('2. Appuyez sur « Envoyer le code » et consultez le SMS.'),
                    _P('3. Saisissez les 6 chiffres. Première utilisation : cochez « Nouveau compte » et choisissez un pseudo.'),
                  ],
                ),
                _section(
                  icon: Icons.sos,
                  title: 'Créer une alerte SOS',
                  children: const [
                    _P('Depuis l\'accueil, appuyez sur le bouton rouge SOS, puis maintenez environ 2 secondes.'),
                    _P('Votre position (lieu + coordonnées) est envoyée ; vos contacts de confiance sont alertés.'),
                    _P('Après l\'envoi, l\'écran affiche le lieu partagé. Vous pouvez Partager ou envoyer via WhatsApp.'),
                    _P('GPS : position actuelle, sinon dernière connue, sinon mémorisée. Activez le GPS pour plus de précision.'),
                    _P('Annulation : « Fausse alerte — annuler » dans les minutes suivant l\'envoi.'),
                    _P('SOS discret (Android) : 3× Volume bas avec l\'app ouverte pour déclencher sans afficher l\'écran SOS.'),
                  ],
                ),
                _section(
                  icon: Icons.people_outline,
                  title: 'Contacts de confiance',
                  children: const [
                    _P('Onglet Confiance → « + Ajouter un contact » : nom et numéro du proche à alerter.'),
                    _P('Ces personnes reçoivent une notification sonore (avec lieu et coordonnées) lorsque vous déclenchez un SOS.'),
                    _P('Alertes SOS (cercle, proximité, groupe, secteur) : son via notification et sirène in-app si l\'app est ouverte — toujours audibles, même en camouflage.'),
                  ],
                ),
                _section(
                  icon: Icons.map_outlined,
                  title: 'Carte et signalements',
                  children: const [
                    _P('Consultez les signalements autour de vous (marqueurs colorés).'),
                    _P('Filtres cliquables Danger / Vigilance / Sûr en haut de la carte (plusieurs peuvent être actifs).'),
                    _P('Filtrez aussi par type et période (24h / 7j). Touchez un marqueur pour les détails : lieu et coordonnées GPS.'),
                    _P('Signalez un incident (bouton rouge) ou confirmez un signalement existant.'),
                    _P('La carte chaleur n\'apparaît sur l\'accueil que si elle est activée côté serveur (masquée par défaut).'),
                  ],
                ),
                _section(
                  icon: Icons.groups_outlined,
                  title: 'Groupes voisins',
                  children: const [
                    _P('Créez un groupe ou rejoignez-en un avec un code d\'invitation.'),
                    _P('Rejoindre un groupe envoie une demande à l\'administrateur du groupe.'),
                    _P('Les admins du groupe voient les demandes en attente et peuvent les traiter.'),
                    _P('Alertes locales : le lieu s\'affiche lorsque la position est disponible.'),
                  ],
                ),
                _section(
                  icon: Icons.home_work_outlined,
                  title: 'Veille quartier',
                  children: const [
                    _P('Accueil → Veille quartier : résumé quotidien des alertes près de chez vous.'),
                  ],
                ),
                _section(
                  icon: Icons.route,
                  title: 'Trajet sécurisé',
                  children: const [
                    _P('Carte en haut : appuyez pour fixer le départ, puis l\'arrivée (bandeau « Appuyez sur la carte… »).'),
                    _P('Saisissez l\'adresse ou utilisez le GPS (« Ma position », icône réticule) sur le champ actif.'),
                    _P('Choisissez le moyen (à pied, moto, véhicule) : la durée est calculée automatiquement, vous pouvez la modifier.'),
                    _P('Après Démarrer, copiez le « code à donner aux proches » (ou le lien) et envoyez-le à la personne qui vous suit. Elle le colle dans « Suivre le trajet ».'),
                    _P('Une fois le trajet démarré, le GPS continue en arrière-plan (notification persistante), même si vous quittez l\'écran Trajet.'),
                    _P('Si vous ne confirmez pas votre arrivée à temps, une alerte peut être déclenchée.'),
                  ],
                ),
                _section(
                  icon: Icons.visibility_off_outlined,
                  title: 'Mode discret',
                  children: const [
                    _P('Désactivé par défaut. Paramètres → « Camouflage calculatrice » pour l\'activer.'),
                    _P('Déverrouillage : tapez 1234= sur la calculatrice (appui long sur l\'afficheur pour le rappel).'),
                    _P('Pour désactiver : Paramètres → désactivez le commutateur Camouflage.'),
                    _P('Code de contrainte (optionnel) : envoie une alerte sans ouvrir l\'application.'),
                    _P('Sonnerie : les alertes SOS reçues restent toujours audibles à priorité max, même en mode camouflage. Seul votre SOS discret (volume / secousse) reste silencieux sur votre téléphone.'),
                  ],
                ),
                if (_isOps)
                  _section(
                    icon: Icons.shield_outlined,
                    title: 'Mode responsable — traiter une alerte',
                    children: const [
                      _P('Accueil ou Paramètres → « Mode responsable ».'),
                      _P('Consultez la liste des incidents du secteur, puis prenez en charge (accusé de réception).'),
                      _P('Assignez un agent si besoin, échangez via le fil de discussion, puis marquez résolu.'),
                      _P('Exportez un rapport PDF pour le suivi hebdomadaire.'),
                    ],
                  ),
                if (_isAdmin)
                  _section(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Administration',
                    children: const [
                      _P('Accueil ou Paramètres → Administration.'),
                      _P('Utilisateurs : changer le rôle et attribuer un secteur. Super administrateur : nommer un admin et activer ou désactiver un compte.'),
                      _P('Abonnements : accorder, prolonger ou révoquer Premium.'),
                      _P('Partenaires API (super administrateur) : créer ou révoquer une clé pour une organisation externe.'),
                      _P('Console web : tableau de bord, abonnements, ops, annuaire, incidents, groupes et mode maintenance.'),
                    ],
                  ),
                _section(
                  icon: Icons.info_outline,
                  title: 'Rôles dans l\'application',
                  children: [
                    const _P('Citoyen : SOS, contacts, carte, groupes, trajets, signalements.'),
                    const _P('Responsable : en plus, Mode responsable pour gérer les incidents du secteur.'),
                    const _P('Agent : même accès responsable, filtré par secteur assigné.'),
                    const _P('Administrateur et super administrateur : utilisateurs, abonnements et rôles. Super administrateur : partenaires API, activation des comptes et mode maintenance.'),
                    _P('Votre profil actuel : $roleLabel.'),
                  ],
                ),
                _section(
                  icon: Icons.traffic_outlined,
                  title: 'Zones Danger / Vigilance / Sûr',
                  children: const [
                    _P('Alerte (rouge) : SOS déclenché.'),
                    _P('Vigilance (orange) : signalement carte (vol, agression…).'),
                    _P('Danger (rouge foncé) : plusieurs confirmations citoyennes sur un signalement.'),
                    _P('Sûr (vert) : un responsable a résolu l\'incident et le quartier est calme.'),
                    _P('Le nom du lieu (quartier) est calculé automatiquement à partir du GPS (OpenStreetMap).'),
                    _P('Sur SOS et signalements, le lieu et les coordonnées sont visibles pour ceux qui consultent l\'alerte.'),
                    _P('Qui fait quoi : citoyen → SOS, signalement, confirmation ; responsable → prise en charge et résolution.'),
                  ],
                ),
                if (_isOps)
                  _section(
                    icon: Icons.place_outlined,
                    title: 'Lieu visible en Mode responsable',
                    children: const [
                      _P('Chaque carte d\'incident affiche le nom de zone et les coordonnées GPS.'),
                      _P('Le filtrage secteur utilise le nom de zone (ex. Gombe) assigné à votre profil.'),
                    ],
                  ),
                _section(
                  icon: Icons.help_outline,
                  title: 'Questions fréquentes',
                  children: const [
                    _P('Code non reçu ? Vérifiez le format du numéro, attendez 1–2 minutes, puis redemandez un code.'),
                    _P('Serveur inaccessible ? Vérifiez votre connexion Internet et réessayez.'),
                    _P('Mode invité : carte et annuaire sans compte. Connexion requise pour SOS, contacts et signalements.'),
                    _P('Suppression de compte : Paramètres → Supprimer le compte (irréversible).'),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    final uri = Uri.parse(_kHostedManualUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  child: const Text('Ouvrir la version web du manuel'),
                ),
                Center(
                  child: Text(
                    'SafeAlert — manuel utilisateur',
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

  Widget _introCard(String roleLabel) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Manuel d\'utilisation',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            'Guide pratique selon votre profil ($roleLabel). Touchez une section pour l\'ouvrir.',
            style: const TextStyle(fontSize: 11, color: Colors.white70, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
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
          leading: Icon(icon, color: AppColors.bleuFonce, size: 22),
          title: Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.bleuFonce),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
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
