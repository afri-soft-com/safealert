import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';

/// Détail d'une zone de confiance : carte, rayon, édition, contacts.
class TrustZoneDetailScreen extends StatefulWidget {
  final Map<String, dynamic> zone;
  final VoidCallback onChanged;

  const TrustZoneDetailScreen({
    super.key,
    required this.zone,
    required this.onChanged,
  });

  @override
  State<TrustZoneDetailScreen> createState() => _TrustZoneDetailScreenState();
}

class _TrustZoneDetailScreenState extends State<TrustZoneDetailScreen> {
  static const _radiusPresets = [50, 100, 200, 300, 500, 1000, 2000];
  static const _radiusMin = 50;
  static const _radiusMax = 5000;

  final _api = ApiService();
  final _mapCtrl = MapController();
  late final TextEditingController _labelCtrl;
  late String _type;
  late int _radiusM;
  late bool _notifyContacts;
  late double _lat;
  late double _lng;
  bool _saving = false;
  bool _dirty = false;

  String get _id => widget.zone['id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    final z = widget.zone;
    _labelCtrl = TextEditingController(text: z['label']?.toString() ?? '');
    _type = z['zone_type']?.toString() ?? 'home';
    _radiusM = (z['radius_m'] as num?)?.toInt() ?? 200;
    _notifyContacts = z['notify_contacts'] != false;
    _lat = (z['lat'] as num?)?.toDouble() ?? 0;
    _lng = (z['lng'] as num?)?.toDouble() ?? 0;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  String _zoneTypeLabel(String? type) {
    switch (type) {
      case 'home':
        return 'Domicile';
      case 'work':
        return 'Travail';
      case 'school':
        return 'École';
      case 'custom':
        return 'Autre';
      default:
        return type ?? 'Zone';
    }
  }

  String _radiusLabel(int m) {
    if (m >= 1000 && m % 1000 == 0) return '${m ~/ 1000} km';
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
    return '$m m';
  }

  double get _mapZoom {
    if (_radiusM >= 2000) return 13;
    if (_radiusM >= 1000) return 14;
    if (_radiusM >= 500) return 15;
    if (_radiusM >= 200) return 16;
    return 17;
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty) {
      showAppSnackBar(context, 'Indiquez un libellé.', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _api.patch('/trust-zones/$_id', {
        'label': label,
        'zone_type': _type,
        'lat': _lat,
        'lng': _lng,
        'radius_m': _radiusM.clamp(_radiusMin, _radiusMax),
        'notify_contacts': _notifyContacts,
      });
      widget.onChanged();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      showAppSnackBar(context, 'Zone mise à jour.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnackBar(
        context,
        e,
        isError: true,
        fallback: 'Enregistrement impossible.',
      );
    }
  }

  Future<void> _recenterHere() async {
    final pos = await LocationService().getCurrentPosition();
    if (pos == null) {
      if (mounted) {
        showAppSnackBar(
          context,
          'GPS indisponible. Activez la localisation.',
          isError: true,
        );
      }
      return;
    }
    setState(() {
      _lat = pos.latitude;
      _lng = pos.longitude;
      _dirty = true;
    });
    try {
      _mapCtrl.move(LatLng(_lat, _lng), _mapZoom);
    } catch (_) {}
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette zone ?'),
        content: Text(
          '« ${_labelCtrl.text.trim().isEmpty ? 'Cette zone' : _labelCtrl.text.trim()} » '
          'ne déclenchera plus d’alertes.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: AppColors.rouge)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.delete('/trust-zones/$_id');
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          e,
          isError: true,
          fallback: 'Suppression impossible.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(_lat, _lng);
    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(
            title: _labelCtrl.text.trim().isEmpty
                ? 'Détail zone'
                : _labelCtrl.text.trim(),
            onBackTap: () => Navigator.pop(context),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                SizedBox(
                  height: 240,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FlutterMap(
                      mapController: _mapCtrl,
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: _mapZoom,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.safealert.safealert',
                        ),
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: center,
                              radius: _radiusM.toDouble(),
                              useRadiusInMeter: true,
                              color: AppColors.bleu.withValues(alpha: 0.18),
                              borderColor: AppColors.bleuFonce,
                              borderStrokeWidth: 2,
                            ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: center,
                              width: 36,
                              height: 36,
                              child: const Icon(
                                Icons.home_work,
                                color: AppColors.bleuFonce,
                                size: 32,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Centre : ${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)} · '
                  'Rayon ${_radiusLabel(_radiusM)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.gris),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Libellé',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    _markDirty();
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Type',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'home', child: Text('Domicile')),
                    DropdownMenuItem(value: 'work', child: Text('Travail')),
                    DropdownMenuItem(value: 'school', child: Text('École')),
                    DropdownMenuItem(value: 'custom', child: Text('Autre')),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _type = v ?? 'home';
                      _dirty = true;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Rayon d\'alerte : ${_radiusLabel(_radiusM)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.bleuFonce,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final m in _radiusPresets)
                      ChoiceChip(
                        label: Text(_radiusLabel(m)),
                        selected: _radiusM == m,
                        onSelected: (_) {
                          setState(() {
                            _radiusM = m;
                            _dirty = true;
                          });
                          try {
                            _mapCtrl.move(center, _mapZoom);
                          } catch (_) {}
                        },
                      ),
                  ],
                ),
                Slider(
                  value: _radiusM.toDouble().clamp(
                    _radiusMin.toDouble(),
                    _radiusMax.toDouble(),
                  ),
                  min: _radiusMin.toDouble(),
                  max: _radiusMax.toDouble(),
                  divisions: 99,
                  label: _radiusLabel(_radiusM),
                  activeColor: AppColors.bleuFonce,
                  onChanged: (v) {
                    setState(() {
                      _radiusM = v.round();
                      _dirty = true;
                    });
                  },
                  onChangeEnd: (_) {
                    try {
                      _mapCtrl.move(LatLng(_lat, _lng), _mapZoom);
                    } catch (_) {}
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Alerter aussi Mes contacts',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _notifyContacts
                        ? 'Vous + vos contacts SafeAlert (app installée)'
                        : 'Vous seul êtes notifié',
                    style: const TextStyle(fontSize: 11, color: AppColors.gris),
                  ),
                  value: _notifyContacts,
                  activeColor: AppColors.bleuFonce,
                  onChanged: (v) {
                    setState(() {
                      _notifyContacts = v;
                      _dirty = true;
                    });
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  'Type : ${_zoneTypeLabel(_type)}. Un SOS dans ce cercle vous '
                  'envoie une notif (écran d’actions).',
                  style: const TextStyle(fontSize: 11, color: AppColors.gris),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _recenterHere,
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text('Recentrer sur ma position GPS'),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _saving || !_dirty ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.bleuFonce,
                    disabledBackgroundColor: AppColors.grisClair,
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined, color: Colors.white),
                  label: Text(
                    _dirty ? 'Enregistrer' : 'À jour',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline, color: AppColors.rouge),
                  label: const Text(
                    'Supprimer la zone',
                    style: TextStyle(color: AppColors.rouge),
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
