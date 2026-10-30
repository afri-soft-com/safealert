import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';
import '../widgets/app_feedback.dart';

class LiveCirclesScreen extends StatefulWidget {
  final VoidCallback onBack;
  const LiveCirclesScreen({super.key, required this.onBack});

  @override
  State<LiveCirclesScreen> createState() => _LiveCirclesScreenState();
}

class _LiveCirclesScreenState extends State<LiveCirclesScreen> {
  final _api = ApiService();
  final _nameCtrl = TextEditingController(text: 'Famille');
  final _codeCtrl = TextEditingController();
  List<Map<String, dynamic>> _circles = [];
  List<Map<String, dynamic>> _members = [];
  String? _selectedId;
  bool _loading = true;
  bool _sharing = false;
  int _shareHours = 24;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
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

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('/live-circles');
      final list = _asMapList(res['data'] ?? res);
      if (!mounted) return;
      setState(() {
        _circles = list;
        _loading = false;
      });
      if (_selectedId != null) await _loadMembers(_selectedId!);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppSnackBar(context, e, isError: true, fallback: 'Impossible de charger les cercles');
    }
  }

  Future<void> _loadMembers(String id) async {
    _poll?.cancel();
    setState(() => _selectedId = id);
    try {
      final res = await _api.get('/live-circles/$id/members');
      final list = _asMapList(res['data'] ?? res);
      if (!mounted) return;
      setState(() => _members = list);
      _poll = Timer.periodic(const Duration(seconds: 20), (_) async {
        if (!mounted || _selectedId == null) return;
        try {
          final r = await _api.get('/live-circles/$_selectedId/members');
          final m = _asMapList(r['data'] ?? r);
          if (mounted) setState(() => _members = m);
        } catch (_) {}
      });
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, e, isError: true, fallback: 'Membres indisponibles');
      }
    }
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showAppSnackBar(context, 'Indiquez un nom pour le cercle.', isError: true);
      return;
    }
    try {
      await _api.post('/live-circles', {'name': name});
      await _refresh();
      if (mounted) {
        showAppSnackBar(context, 'Cercle créé. Partagez le code d\'invitation.');
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, e, isError: true, fallback: 'Création impossible');
      }
    }
  }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 4) {
      showAppSnackBar(context, 'Code d\'invitation trop court.', isError: true);
      return;
    }
    try {
      await _api.post('/live-circles/join', {'code': code});
      _codeCtrl.clear();
      await _refresh();
      if (mounted) {
        showAppSnackBar(context, 'Vous avez rejoint le cercle.');
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, e, isError: true, fallback: 'Code invalide');
      }
    }
  }

  Future<void> _shareMyLocation() async {
    final id = _selectedId;
    if (id == null) {
      showAppSnackBar(context, 'Sélectionnez un cercle d\'abord.', isError: true);
      return;
    }
    setState(() => _sharing = true);
    try {
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

      // Circle share needs server-side share_presence + last_lat/lng, otherwise
      // membersLive filters the user out even after share_until is set.
      final auth = context.read<AuthProvider>();
      if (!auth.sharePresence) {
        final ok = await auth.updateProfile(sharePresence: true);
        if (!ok) {
          if (mounted) {
            showAppSnackBar(
              context,
              'Activez « Partager ma présence » dans Réglages pour apparaître sur la carte.',
              isError: true,
            );
          }
          return;
        }
      }
      LocationService().sharePresence = true;
      await LocationService().updatePosition(
        pos.latitude,
        pos.longitude,
        force: true,
      );
      await _api.patch('/live-circles/$id/share', {'hours': _shareHours});
      LocationService().startPeriodicUpdates(
        interval: const Duration(minutes: 1),
      );
      await _loadMembers(id);
      if (mounted) {
        showAppSnackBar(
          context,
          'Position partagée pendant $_shareHours h avec ce cercle.',
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          e,
          isError: true,
          fallback: 'Impossible de partager la position.',
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final markers = _members
        .where((m) => m['last_lat'] != null && m['last_lng'] != null)
        .map((m) {
      final lat = (m['last_lat'] as num).toDouble();
      final lng = (m['last_lng'] as num).toDouble();
      return Marker(
        point: LatLng(lat, lng),
        width: 40,
        height: 40,
        child: Tooltip(
          message: m['pseudo']?.toString() ?? 'Membre',
          child: const Icon(Icons.person_pin_circle, color: AppColors.vert, size: 36),
        ),
      );
    }).toList();

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(title: 'Cercles famille', onBackTap: widget.onBack),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Partagez votre position temporairement avec vos proches (consentement requis).',
                  style: TextStyle(fontSize: 12, color: AppColors.gris),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom du cercle',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _create,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.bleuFonce),
                  child: const Text('Créer un cercle', style: TextStyle(color: Colors.white)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _codeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Code invitation',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _join, child: const Text('Rejoindre')),
                const SizedBox(height: 16),
                if (_loading) const Center(child: CircularProgressIndicator()),
                if (!_loading && _circles.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Aucun cercle. Créez-en un ou rejoignez avec un code.',
                      style: TextStyle(fontSize: 12, color: AppColors.gris),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ..._circles.map((c) {
                  final id = c['id']?.toString() ?? '';
                  final selected = id == _selectedId;
                  final role = c['my_role']?.toString();
                  return ListTile(
                    selected: selected,
                    selectedTileColor: AppColors.bleu.withValues(alpha: 0.08),
                    title: Text(c['name']?.toString() ?? 'Cercle'),
                    subtitle: Text(
                      'Code : ${c['invite_code'] ?? '—'}'
                      '${role != null ? ' · $role' : ''}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Copier le code',
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: c['invite_code']?.toString() ?? ''),
                        );
                        showAppSnackBar(context, 'Code copié');
                      },
                    ),
                    onTap: () => _loadMembers(id),
                  );
                }),
                if (_selectedId != null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Partage de position',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.bleuFonce,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    value: _shareHours,
                    decoration: const InputDecoration(
                      labelText: 'Durée',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 heure')),
                      DropdownMenuItem(value: 6, child: Text('6 heures')),
                      DropdownMenuItem(value: 12, child: Text('12 heures')),
                      DropdownMenuItem(value: 24, child: Text('24 heures')),
                      DropdownMenuItem(value: 48, child: Text('48 heures')),
                      DropdownMenuItem(value: 72, child: Text('72 heures')),
                    ],
                    onChanged: (v) => setState(() => _shareHours = v ?? 24),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _sharing ? null : _shareMyLocation,
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.vert),
                    icon: _sharing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.my_location, color: Colors.white),
                    label: Text(
                      _sharing ? 'Partage…' : 'Partager ma position GPS',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: markers.isNotEmpty
                              ? markers.first.point
                              : const LatLng(-4.3217, 15.3125),
                          initialZoom: 12,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.safealert.safealert',
                          ),
                          MarkerLayer(markers: markers),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    _members.isEmpty
                        ? 'Aucun membre visible pour l’instant. Partagez votre GPS ou invitez un proche avec le code.'
                        : '${_members.length} membre(s) visibles (rafraîchi toutes les 20 s)',
                    style: const TextStyle(fontSize: 11, color: AppColors.gris),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
