import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../utils/location_format.dart';
import '../utils/open_maps.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';
import 'group_detail_screen.dart';

/// Écran destinataire quand on ouvre une notif SOS / alerte proche.
class IncomingSosScreen extends StatelessWidget {
  final Map<String, String> data;
  final VoidCallback onBack;
  final void Function(String screen) onNavigate;

  const IncomingSosScreen({
    super.key,
    required this.data,
    required this.onBack,
    required this.onNavigate,
  });

  String get _type => (data['type'] ?? 'sos_alert').trim();

  bool get _isFalseAlarm =>
      _type == 'false_alarm' ||
      _type == 'group_false_alarm' ||
      _type == 'group_safe';

  String get _pseudo {
    final p = (data['pseudo'] ?? '').trim();
    return p.isNotEmpty ? p : 'Un proche';
  }

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

  String? get _zoneName {
    final z = (data['zone_name'] ?? data['zoneName'] ?? '').trim();
    return z.isNotEmpty ? z : null;
  }

  String? get _groupId {
    final g = (data['groupId'] ?? data['group_id'] ?? '').trim();
    return g.isNotEmpty ? g : null;
  }

  String? get _zoneLabel {
    final z = (data['zoneLabel'] ?? data['label'] ?? '').trim();
    return z.isNotEmpty ? z : null;
  }

  bool get _hasLocation => _lat != null && _lng != null;

  String get _headline {
    if (_type == 'group_safe') return 'En sécurité';
    if (_isFalseAlarm) return 'Fausse alerte';
    if (_type == 'trust_zone_alert') {
      return _zoneLabel != null
          ? 'SOS près de $_zoneLabel'
          : 'SOS près d’une zone de confiance';
    }
    if (_type == 'nearby_alert') return 'Alerte à proximité';
    if (_type == 'group_sos' || _type == 'group_report') return 'Alerte groupe';
    if (_type == 'sector_sos') return 'Alerte secteur';
    return 'SOS — besoin d’aide';
  }

  String get _body {
    if (_type == 'group_safe') {
      return '$_pseudo confirme être en sécurité. Aucune intervention nécessaire.';
    }
    if (_isFalseAlarm) {
      return '$_pseudo a annulé son SOS. Situation sous contrôle.';
    }
    if (_type == 'trust_zone_alert') {
      return 'Un SOS a été signalé près de votre zone de confiance. '
          'Contactez vos proches ou allez vérifier si c’est sûr.';
    }
    return '$_pseudo a besoin d’aide. Appelez, ouvrez l’itinéraire, '
        'ou contactez les secours si nécessaire.';
  }

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
          const SnackBar(content: Text('Impossible d’ouvrir le composeur')),
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
    await openExternalMapsOrSnack(context, _lat, _lng, label: _headline);
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
    final accent = _isFalseAlarm ? AppColors.vert : AppColors.rouge;
    final accentBg = _isFalseAlarm ? AppColors.vertClair : AppColors.rougeLight;

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(title: _headline, onBackTap: onBack),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accentBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _pseudo,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _body,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: AppColors.bleuFonce,
                        ),
                      ),
                      if (_zoneName != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          '📍 $_zoneName',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.bleuFonce,
                          ),
                        ),
                      ],
                      if (_hasLocation) ...[
                        const SizedBox(height: 6),
                        Text(
                          LocationFormat.displayLine(lat: _lat, lng: _lng),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.bleuFonce,
                          ),
                        ),
                      ] else if (!_isFalseAlarm) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'Position précise indisponible dans la notification.',
                          style: TextStyle(fontSize: 12, color: AppColors.gris),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!_isFalseAlarm) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Actions',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.gris,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _actionBtn(
                    icon: Icons.phone,
                    label: _phone != null
                        ? 'Appeler $_pseudo'
                        : 'Appeler (numéro indisponible)',
                    color: AppColors.vert,
                    onTap: _phone != null ? () => _call(context) : null,
                  ),
                  const SizedBox(height: 8),
                  _actionBtn(
                    icon: Icons.map_outlined,
                    label: _hasLocation
                        ? 'Itinéraire vers $_pseudo'
                        : 'Itinéraire (position indisponible)',
                    color: AppColors.bleuFonce,
                    onTap: _hasLocation ? () => _openMaps(context) : null,
                  ),
                  const SizedBox(height: 8),
                  _actionBtn(
                    icon: Icons.map,
                    label: 'Voir la carte SafeAlert',
                    color: AppColors.bleuFonce,
                    onTap: () => onNavigate('map'),
                  ),
                  if (_groupId != null ||
                      _type == 'group_sos' ||
                      _type == 'group_report') ...[
                    const SizedBox(height: 8),
                    _actionBtn(
                      icon: Icons.groups_outlined,
                      label: _groupId != null
                          ? 'Ouvrir le groupe (Alertes)'
                          : 'Voir mes groupes',
                      color: AppColors.bleuFonce,
                      onTap: () => _openGroup(context),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _actionBtn(
                    icon: Icons.phone_in_talk_outlined,
                    label: 'Annuaire d’urgence',
                    color: AppColors.rouge,
                    onTap: () => onNavigate('annuaire'),
                  ),
                ] else ...[
                  const SizedBox(height: 20),
                  _actionBtn(
                    icon: Icons.check_circle_outline,
                    label: 'Compris',
                    color: AppColors.vert,
                    onTap: onBack,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
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
          backgroundColor:
              enabled ? color : AppColors.gris.withValues(alpha: 0.35),
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
