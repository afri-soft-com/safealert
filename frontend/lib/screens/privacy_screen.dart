import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/status_bar.dart';

class PrivacyScreen extends StatefulWidget {
  final VoidCallback onBack;
  const PrivacyScreen({super.key, required this.onBack});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  String _title = 'Politique de confidentialité';
  String _version = '';
  String _body = '';
  bool _loading = true;
  bool _fromApi = false;

  static const _fallbackBody = '''SafeAlert — Politique de confidentialité

Dernière mise à jour : août 2026

1. Données collectées
SafeAlert collecte votre numéro de téléphone, pseudo, position GPS (lors des alertes ou mises à jour volontaires), contacts de confiance, et historique d'incidents que vous signalez ou recevez. Connexion Google / Apple : e-mail et identifiant le cas échéant.

2. Utilisation des données
Vos données servent à authentifier votre compte, envoyer des alertes SOS à vos contacts et voisins proches, afficher les incidents sur la carte communautaire, et améliorer la sécurité de votre quartier.

3. Partage des données
Vos alertes SOS sont partagées avec vos contacts de confiance et les utilisateurs à proximité. Les signalements anonymes masquent votre identité. Nous ne vendons pas vos données à des tiers.

4. Localisation
La position GPS n'est transmise que lorsque vous déclenchez une alerte, signalez un incident, ou lorsque l'application met à jour votre position (si autorisé).

5. Conservation
Les incidents sont conservés pour l'historique communautaire. Vous pouvez supprimer votre compte depuis les paramètres.

6. Sécurité
Communications HTTPS, OTP hashés (expiration 5 min), jetons stockés localement.

7. Vos droits
Accès, rectification ou suppression via « Supprimer le compte » ou le support store.

8. Contact
Canal de contact de la fiche store SafeAlert.''';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/legal/privacy');
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final body = (json['body'] as String?)?.trim() ?? '';
        if (body.isNotEmpty && mounted) {
          setState(() {
            _title = (json['title'] as String?)?.trim().isNotEmpty == true
                ? json['title'] as String
                : _title;
            _version = (json['version'] as String?)?.trim() ?? '';
            _body = body;
            _fromApi = true;
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _body = _fallbackBody;
      _loading = false;
    });
  }

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
                  onTap: widget.onBack,
                  child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Politique de confidentialité',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        _title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.bleuFonce,
                        ),
                      ),
                      if (_version.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Version $_version${_fromApi ? '' : ' (hors ligne)'}',
                          style: const TextStyle(fontSize: 11, color: AppColors.gris),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        _body,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.bleuFonce,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
