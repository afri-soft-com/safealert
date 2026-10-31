import 'package:flutter/material.dart';
import '../theme.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';
import 'trust_zone_detail_screen.dart';

class TrustZonesScreen extends StatefulWidget {
  final VoidCallback onBack;
  const TrustZonesScreen({super.key, required this.onBack});

  @override
  State<TrustZonesScreen> createState() => _TrustZonesScreenState();
}

class _TrustZonesScreenState extends State<TrustZonesScreen> {
  static const _radiusPresets = [50, 100, 200, 300, 500, 1000, 2000];
  static const _radiusMin = 50;
  static const _radiusMax = 5000;

  final _api = ApiService();
  List<Map<String, dynamic>> _zones = [];
  bool _loading = true;
  String _type = 'home';
  int _radiusM = 200;
  final _labelCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _asMapList(dynamic raw) {
    final list = raw is List
        ? raw
        : (raw is Map && raw['data'] is List ? raw['data'] as List : null);
    if (list == null) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('/trust-zones');
      _zones = _asMapList(res['data'] ?? res);
    } catch (e) {
      _zones = [];
      if (mounted) {
        showAppSnackBar(
          context,
          e,
          isError: true,
          fallback: 'Impossible de charger les zones.',
        );
      }
    }
    if (mounted) setState(() => _loading = false);
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

  Future<void> _add() async {
    final pos = await LocationService().getCurrentPosition();
    if (pos == null) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Localisation indisponible. Activez le GPS et réessayez.',
          isError: true,
        );
      }
      return;
    }
    if (_labelCtrl.text.trim().isEmpty) {
      if (mounted) {
        showAppSnackBar(context, 'Indiquez un libellé pour cette zone.', isError: true);
      }
      return;
    }
    final radius = _radiusM.clamp(_radiusMin, _radiusMax);
    try {
      await _api.post('/trust-zones', {
        'label': _labelCtrl.text.trim(),
        'zone_type': _type,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'radius_m': radius,
      });
      _labelCtrl.clear();
      await _load();
      if (mounted) {
        showAppSnackBar(
          context,
          'Zone ajoutée (rayon ${_radiusLabel(radius)})',
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          e,
          isError: true,
          fallback: 'Impossible d\'ajouter cette zone. Activez la localisation et réessayez.',
        );
      }
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(title: l10n.trustZones, onBackTap: widget.onBack),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Si un SOS est déclenché dans le rayon de votre zone, '
                        'vous êtes notifié, ainsi que vos contacts SafeAlert '
                        '(Mes contacts) qui ont l\'application.',
                        style: TextStyle(fontSize: 12, color: AppColors.gris),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _labelCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Libellé',
                          border: OutlineInputBorder(),
                        ),
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
                        onChanged: (v) => setState(() => _type = v ?? 'home'),
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
                      const SizedBox(height: 6),
                      const Text(
                        'Tout SOS dans ce rayon vous alerte (et vos contacts inscrits). '
                        'Ajoutez au moins un contact SafeAlert pour élargir l\'entraide.',
                        style: TextStyle(fontSize: 11, color: AppColors.gris),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final m in _radiusPresets)
                            ChoiceChip(
                              label: Text(_radiusLabel(m)),
                              selected: _radiusM == m,
                              onSelected: (_) => setState(() => _radiusM = m),
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
                        onChanged: (v) => setState(() => _radiusM = v.round()),
                      ),
                      Text(
                        'Entre $_radiusMin m et ${_radiusLabel(_radiusMax)}',
                        style: const TextStyle(fontSize: 10, color: AppColors.gris),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _add,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.bleu),
                        child: const Text(
                          'Ajouter ici (GPS actuel)',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_zones.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'Aucune zone de confiance. Ajoutez votre domicile ou votre travail.',
                            style: TextStyle(fontSize: 12, color: AppColors.gris),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        ..._zones.map(
                          (z) => ListTile(
                            title: Text(z['label'] as String? ?? ''),
                            subtitle: Text(
                              '${_zoneTypeLabel(z['zone_type'] as String?)} · '
                              'Rayon : ${_radiusLabel((z['radius_m'] as num?)?.toInt() ?? 200)}'
                              '${z['notify_contacts'] == false ? ' · vous seul' : ' · + contacts'}',
                            ),
                            trailing: const Icon(Icons.chevron_right, color: AppColors.gris),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => TrustZoneDetailScreen(
                                    zone: Map<String, dynamic>.from(z),
                                    onChanged: _load,
                                  ),
                                ),
                              );
                              if (mounted) await _load();
                            },
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
