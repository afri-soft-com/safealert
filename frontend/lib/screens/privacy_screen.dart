import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/status_bar.dart';

class PrivacyScreen extends StatelessWidget {
  final VoidCallback onBack;
  const PrivacyScreen({super.key, required this.onBack});

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
                const Text('Politique de confidentialité',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                Text('SafeAlert — Politique de confidentialité (MVP)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
                SizedBox(height: 12),
                Text('Dernière mise à jour : juin 2026',
                    style: TextStyle(fontSize: 11, color: AppColors.gris)),
                SizedBox(height: 16),
                _Section(
                  title: '1. Données collectées',
                  body: 'SafeAlert collecte votre numéro de téléphone, pseudo, position GPS (lors des alertes ou mises à jour volontaires), contacts de confiance, et historique d\'incidents que vous signalez ou recevez.',
                ),
                _Section(
                  title: '2. Utilisation des données',
                  body: 'Vos données servent à authentifier votre compte, envoyer des alertes SOS à vos contacts et voisins proches, afficher les incidents sur la carte communautaire, et améliorer la sécurité de votre quartier.',
                ),
                _Section(
                  title: '3. Partage des données',
                  body: 'Vos alertes SOS sont partagées avec vos contacts de confiance et les utilisateurs à proximité (rayon ~500 m). Les signalements anonymes masquent votre identité. Nous ne vendons pas vos données à des tiers.',
                ),
                _Section(
                  title: '4. Localisation',
                  body: 'La position GPS n\'est transmise que lorsque vous déclenchez une alerte, signalez un incident, ou lorsque l\'application met à jour votre position en arrière-plan (si autorisé). Vous pouvez refuser l\'accès à la localisation dans les paramètres de votre appareil.',
                ),
                _Section(
                  title: '5. Conservation',
                  body: 'Les incidents sont conservés pour permettre l\'historique et les statistiques communautaires. Vous pouvez supprimer votre compte depuis les paramètres, ce qui efface vos données personnelles associées.',
                ),
                _Section(
                  title: '6. Sécurité',
                  body: 'Les communications avec nos serveurs sont chiffrées (HTTPS). Les codes OTP expirent après 5 minutes. Les tokens d\'authentification sont stockés localement sur votre appareil.',
                ),
                _Section(
                  title: '7. Vos droits',
                  body: 'Vous pouvez accéder à vos données, les corriger ou demander leur suppression en contactant l\'équipe SafeAlert ou via la fonction « Supprimer le compte » dans l\'application.',
                ),
                _Section(
                  title: '8. Contact',
                  body: 'Pour toute question : contact@safealert.app (adresse à configurer pour la production).',
                ),
                SizedBox(height: 24),
                Text(
                  'En utilisant SafeAlert, vous acceptez cette politique. Une version complète sera publiée avant le déploiement public.',
                  style: TextStyle(fontSize: 11, color: AppColors.gris, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
          const SizedBox(height: 4),
          Text(body, style: const TextStyle(fontSize: 12, color: AppColors.bleuFonce, height: 1.4)),
        ],
      ),
    );
  }
}
