import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../services/api_service.dart';
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
    try {
      await _api.post('/live-circles', {'name': _nameCtrl.text.trim()});
      await _refresh();
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, e, isError: true, fallback: 'Création impossible');
      }
    }
  }

  Future<void> _join() async {
    try {
      await _api.post('/live-circles/join', {'code': _codeCtrl.text.trim()});
      _codeCtrl.clear();
      await _refresh();
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, e, isError: true, fallback: 'Code invalide');
      }
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
                  'Partagez votre position temporairement avec proches (consentement requis).',
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
                ElevatedButton(onPressed: _create, child: const Text('Créer un cercle')),
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
                ..._circles.map((c) {
                  final id = c['id']?.toString() ?? '';
                  final selected = id == _selectedId;
                  return ListTile(
                    selected: selected,
                    title: Text(c['name']?.toString() ?? 'Cercle'),
                    subtitle: Text('Code : ${c['invite_code'] ?? '—'}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: c['invite_code']?.toString() ?? ''));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copié')),
                        );
                      },
                    ),
                    onTap: () => _loadMembers(id),
                  );
                }),
                if (_selectedId != null) ...[
                  const SizedBox(height: 8),
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
                  Text('${_members.length} membre(s) visibles',
                      style: const TextStyle(fontSize: 11, color: AppColors.gris)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
