import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../utils/location_format.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';
import 'group_detail_screen.dart';

/// Écran destinataire après un contrôle « Je rentre » sans réponse.
class SafetyPingMissedScreen extends StatelessWidget {
  final Map<String, String> data;
  final VoidCallback onBack;
  final void Function(String screen) onNavigate;

  const SafetyPingMissedScreen({
    super.key,
    required this.data,
    required this.onBack,
    required this.onNavigate,
  });

  String get _pseudo =>
      (data['pseudo'] ?? '').trim().isNotEmpty ? data['pseudo']!.trim() : 'Un proche';

  String? get _phone {
    final p = (data['phone'] ?? '').trim();
    return p.isNotEmpty ? p : null;
  }

  double? get _lat {
    final v = data['lat'];
    if (v == null || v.isEmpty) return null;
    return double.tryParse(v);
  }

  double? get _lng {
    final v = data['lng'];
    if (v == null || v.isEmpty) return null;
    return double.tryParse(v);
  }

  String? get _groupId {
    final g = (data['groupId'] ?? data['group_id'] ?? '').trim();
    return g.isNotEmpty ? g : null;
  }

  bool get _hasLocation => _lat != null && _lng != null;

  Future<void> _call(BuildContext context) async {
    final phone = _phone;
    if (phone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Numéro indisponible')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir le composeur')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appel impossible')),
        );
      }
    }
  }

  Future<void> _openMaps(BuildContext context) async {
    final la = _lat;
    final ln = _lng;
    if (la == null || ln == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Position indisponible pour l\'itinéraire')),
      );
      return;
    }
    final candidates = <Uri>[
      Uri.parse('geo:$la,$ln?q=$la,$ln'),
      Uri.parse('google.navigation:q=$la,$ln'),
      Uri.parse('https://maps.google.com/?q=$la,$ln'),
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$la,$ln'),
    ];
    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {}
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir la carte')),
      );
    }
  }

  void _openGroup(BuildContext context) {
    final id = _groupId;
    if (id == null) {
      onNavigate('groups');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupDetailScreen(
          group: {'id': id, 'name': 'Groupe'},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(title: 'Contrôle sans réponse', onBackTap: onBack),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.orange),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _pseudo,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.bleuFonce,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'N\'a pas confirmé être OK à temps. '
                        'Contactez-le/la ou allez vérifier si c\'est sûr.',
                        style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.bleuFonce),
                      ),
                      if (_hasLocation) ...[
                        const SizedBox(height: 10),
                        Text(
                          '📍 ${LocationFormat.displayLine(lat: _lat, lng: _lng)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.bleuFonce,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 10),
                        const Text(
                          'Position indisponible (partage désactivé ou jamais enregistrée).',
                          style: TextStyle(fontSize: 12, color: AppColors.gris),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Actions',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gris),
                ),
                const SizedBox(height: 10),
                _actionBtn(
                  context,
                  icon: Icons.phone,
                  label: _phone != null ? 'Appeler $_pseudo' : 'Appeler (numéro indisponible)',
                  color: AppColors.vert,
                  onTap: _phone != null ? () => _call(context) : null,
                ),
                const SizedBox(height: 8),
                _actionBtn(
                  context,
                  icon: Icons.map_outlined,
                  label: _hasLocation ? 'Itinéraire' : 'Itinéraire (position indisponible)',
                  color: AppColors.bleuFonce,
                  onTap: _hasLocation ? () => _openMaps(context) : null,
                ),
                const SizedBox(height: 8),
                _actionBtn(
                  context,
                  icon: Icons.groups_outlined,
                  label: _groupId != null ? 'Ouvrir le groupe' : 'Voir mes groupes',
                  color: AppColors.bleuFonce,
                  onTap: () => _openGroup(context),
                ),
                const SizedBox(height: 8),
                _actionBtn(
                  context,
                  icon: Icons.phone_in_talk_outlined,
                  label: 'Annuaire d\'urgence',
                  color: AppColors.rouge,
                  onTap: () => onNavigate('annuaire'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? color : AppColors.gris.withValues(alpha: 0.35),
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.gris.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white70,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}
