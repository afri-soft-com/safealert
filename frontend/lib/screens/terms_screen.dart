import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/status_bar.dart';

class TermsScreen extends StatelessWidget {
  final VoidCallback onBack;
  const TermsScreen({super.key, required this.onBack});

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
                    'Conditions générales d’utilisation',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                Text(
                  'SafeAlert — Conditions générales d’utilisation',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.bleuFonce),
                ),
                SizedBox(height: 12),
                Text(
                  'Dernière mise à jour : septembre 2026',
                  style: TextStyle(fontSize: 11, color: AppColors.gris),
                ),
                SizedBox(height: 16),
                _Section(
                  title: '1. Éditeur et objet',
                  body:
                      'SafeAlert est un service de sécurité citoyenne édité par AfriSoft (afri-soft.com). '
                      'Il permet d’envoyer des alertes SOS, d’informer des contacts de confiance et de consulter '
                      'une carte communautaire des incidents. Ces CGU encadrent l’usage de l’application mobile, '
                      'de l’API et de la console d’administration.',
                ),
                _Section(
                  title: '2. Compte',
                  body:
                      'L’accès se fait par numéro de téléphone et code SMS, puis éventuellement un code PIN local. '
                      'Vous êtes responsable de la confidentialité de votre appareil et de votre PIN. '
                      'Un compte peut être désactivé en cas d’abus.',
                ),
                _Section(
                  title: '3. Usage responsable',
                  body:
                      'SafeAlert est destiné aux situations réelles de danger ou d’entraide de quartier. '
                      'Les fausses alertes, le harcèlement, l’usurpation d’identité et tout usage illégal sont interdits. '
                      'En cas d’urgence vitale, contactez aussi les services publics compétents.',
                ),
                _Section(
                  title: '4. Localisation et alertes',
                  body:
                      'La position n’est transmise que lorsque vous déclenchez une alerte, un signalement, '
                      'ou une fonction qui l’exige (trajet, présence), et si vous l’avez autorisée. '
                      'Vos contacts de confiance et, selon le contexte, la communauté proche peuvent voir l’alerte.',
                ),
                _Section(
                  title: '5. Disponibilité',
                  body:
                      'Le service est fourni « en l’état ». Un SOS dépend du réseau, du GPS et des serveurs. '
                      'AfriSoft ne garantit pas une intervention physique et n’est pas un service d’urgence officiel.',
                ),
                _Section(
                  title: '6. Données personnelles',
                  body:
                      'Le traitement des données est décrit dans la politique de confidentialité. '
                      'Vous pouvez supprimer votre compte depuis les paramètres de l’application.',
                ),
                _Section(
                  title: '7. Contact',
                  body:
                      'Éditeur : AfriSoft — produit SafeAlert. Pas d’adresse postale publique à ce jour. '
                      'Contact : fiche Google Play « SafeAlert » ou le support indiqué par AfriSoft.',
                ),
                SizedBox(height: 24),
                Text(
                  'En utilisant SafeAlert, vous acceptez ces conditions. Une version plus détaillée pourra être publiée ultérieurement.',
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
