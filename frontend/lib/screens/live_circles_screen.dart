import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/circle_mesh_service.dart';
import '../services/geocode_service.dart';
import '../services/local_database.dart';
import '../services/location_service.dart';
import '../utils/map_zoom.dart';
import '../utils/open_maps.dart';
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
  final _mapCtrl = MapController();
  List<Map<String, dynamic>> _circles = [];
  List<Map<String, dynamic>> _members = [];
  String? _selectedId;
  bool _loading = true;
  bool _sharing = false;
  int _shareHours = 24;
  Timer? _poll;
  bool _offlineMode = false;
  /// Recenter map only on first member load / explicit focus — not every poll.
  bool _mapNeedsFit = true;
  final _mesh = CircleMeshService();
  final _cache = LocalDatabase();

  @override
  void initState() {
    super.initState();
    _mesh.addListener(_onMeshUpdate);
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _mesh.removeListener(_onMeshUpdate);
    unawaited(_mesh.stop());
    LocationService().stopCircleLiveShare();
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  void _onMeshUpdate() {
    if (!mounted || _selectedId == null) return;
    // Do not re-center on every mesh packet — that fights user pan/zoom and
    // makes members look stationary when the camera keeps jumping.
    setState(() {
      _members = _mergeMeshIntoMembers(_members);
    });
  }

  List<Map<String, dynamic>> _mergeMeshIntoMembers(
    List<Map<String, dynamic>> base,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final m in base) {
      final id = m['user_id']?.toString() ?? m['id']?.toString();
      if (id == null) continue;
      byId[id] = Map<String, dynamic>.from(m);
    }
    for (final entry in _mesh.peers.entries) {
      final peer = entry.value;
      final existing = byId[entry.key];
      if (existing == null) {
        byId[entry.key] = Map<String, dynamic>.from(peer);
      } else {
        existing['last_lat'] = peer['last_lat'];
        existing['last_lng'] = peer['last_lng'];
        existing['visible_on_map'] = true;
        existing['mesh'] = true;
        existing['share_until'] =
            existing['share_until'] ?? peer['share_until'];
        if ((existing['pseudo'] == null ||
                existing['pseudo'].toString().isEmpty) &&
            peer['pseudo'] != null) {
          existing['pseudo'] = peer['pseudo'];
        }
      }
    }
    return byId.values.toList();
  }

  Future<void> _ensureMesh({required bool sharing}) async {
    final circle = _selectedCircle;
    final id = _selectedId;
    if (circle == null || id == null) return;
    final code = circle['invite_code']?.toString() ?? '';
    if (code.isEmpty) return;
    final auth = context.read<AuthProvider>();
    final uid = auth.user?['id']?.toString();
    if (uid == null || uid.isEmpty) return;
    final pseudo = auth.user?['pseudo']?.toString() ?? 'Moi';
    await _mesh.start(
      circleId: id,
      inviteCode: code,
      userId: uid,
      pseudo: pseudo,
      shareOwnPosition: sharing,
    );
    await _mesh.setSharing(sharing);
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

  Map<String, dynamic>? get _selectedCircle {
    if (_selectedId == null) return null;
    for (final c in _circles) {
      if (c['id']?.toString() == _selectedId) return c;
    }
    return null;
  }

  bool get _amSharing {
    final until = _selectedCircle?['share_until']?.toString();
    if (until == null || until.isEmpty) return false;
    final t = DateTime.tryParse(until);
    return t != null && t.isAfter(DateTime.now());
  }

  bool get _isOwner => _selectedCircle?['my_role']?.toString() == 'owner';

  Future<void> _refresh({String? selectId}) async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('/live-circles');
      final list = _asMapList(res['data'] ?? res);
      await _cache.put('live_circles', list);
      if (!mounted) return;
      final prefer = selectId ?? _selectedId;
      final stillThere =
          prefer != null && list.any((c) => c['id']?.toString() == prefer);
      setState(() {
        _circles = list;
        _loading = false;
        _offlineMode = false;
        _selectedId = stillThere ? prefer : null;
        if (!stillThere) _members = [];
      });
      if (_selectedId != null) await _loadMembers(_selectedId!);
    } catch (e) {
      final cached = await _cache.get('live_circles', maxAgeSeconds: 86400 * 14);
      final list = cached is List
          ? cached
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      if (list.isEmpty) {
        setState(() => _loading = false);
        showAppSnackBar(
          context,
          e,
          isError: true,
          fallback: 'Impossible de charger les cercles',
        );
        return;
      }
      final prefer = selectId ?? _selectedId;
      final stillThere =
          prefer != null && list.any((c) => c['id']?.toString() == prefer);
      setState(() {
        _circles = list;
        _loading = false;
        _offlineMode = true;
        _selectedId = stillThere ? prefer : null;
        if (!stillThere) _members = [];
      });
      if (_selectedId != null) await _loadMembers(_selectedId!);
      if (mounted) {
        showAppSnackBar(
          context,
          'Hors ligne — cercle en mode proximité (Wi‑Fi local / Bluetooth).',
        );
      }
    }
  }

  Future<void> _loadMembers(String id) async {
    _poll?.cancel();
    _mapNeedsFit = true;
    setState(() => _selectedId = id);
    await _ensureMesh(sharing: _amSharing);
    if (_amSharing) {
      LocationService().startCircleLiveShare(
        heartbeat: const Duration(seconds: 8),
        distanceFilterMeters: 8,
      );
    }
    try {
      await _pullMembers(id);
      _poll = Timer.periodic(const Duration(seconds: 5), (_) async {
        if (!mounted || _selectedId == null) return;
        await _pullMembers(_selectedId!);
      });
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, e, isError: true, fallback: 'Membres indisponibles');
      }
    }
  }

  Future<void> _pullMembers(String id) async {
    // Push our GPS first so peers see movement (API + mesh).
    if (_amSharing || _mesh.sharing) {
      await LocationService().syncCurrentPosition(force: true);
    }
    try {
      final res = await _api.get('/live-circles/$id/members');
      final list = _asMapList(res['data'] ?? res);
      await _cache.put('live_circle_members_$id', list);
      if (!mounted || _selectedId != id) return;
      setState(() {
        _offlineMode = false;
        _members = _mergeMeshIntoMembers(list);
      });
      _moveMapToVisible();
    } catch (_) {
      final cached =
          await _cache.get('live_circle_members_$id', maxAgeSeconds: 86400);
      final list = cached is List
          ? cached
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted || _selectedId != id) return;
      setState(() {
        _offlineMode = true;
        _members = _mergeMeshIntoMembers(list);
      });
      _moveMapToVisible();
    }
  }

  void _moveMapToVisible({bool force = false}) {
    if (!force && !_mapNeedsFit) return;
    final points = <LatLng>[];
    for (final m in _visibleMembers) {
      final lat = (m['last_lat'] as num?)?.toDouble();
      final lng = (m['last_lng'] as num?)?.toDouble();
      if (lat != null && lng != null) points.add(LatLng(lat, lng));
    }
    if (points.isEmpty) return;
    try {
      if (points.length == 1) {
        _mapCtrl.move(points.first, MapZoom.circleFocus);
      } else {
        _mapCtrl.fitCamera(
          CameraFit.coordinates(
            coordinates: points,
            padding: const EdgeInsets.all(56),
            maxZoom: MapZoom.circleFocus,
            minZoom: 13,
          ),
        );
      }
      _mapNeedsFit = false;
    } catch (_) {
      try {
        _mapCtrl.move(points.first, MapZoom.circleFocus);
        _mapNeedsFit = false;
      } catch (_) {}
    }
  }

  void _focusMember(Map<String, dynamic> member) {
    final lat = (member['last_lat'] as num?)?.toDouble();
    final lng = (member['last_lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    try {
      _mapCtrl.move(LatLng(lat, lng), MapZoom.circleFocus);
    } catch (_) {}
  }

  /// Android flutter_map markers often swallow GestureDetector taps inside a
  /// ListView — resolve the nearest visible member from a map tap instead.
  void _onMapTap(TapPosition tap, LatLng point) {
    Map<String, dynamic>? best;
    var bestMeters = 80.0;
    const dist = Distance();
    for (final m in _visibleMembers) {
      final la = (m['last_lat'] as num?)?.toDouble();
      final ln = (m['last_lng'] as num?)?.toDouble();
      if (la == null || ln == null) continue;
      final meters = dist.as(LengthUnit.Meter, point, LatLng(la, ln));
      if (meters < bestMeters) {
        bestMeters = meters;
        best = m;
      }
    }
    if (best != null) {
      _showMemberDetails(best);
    }
  }

  Future<void> _showMemberDetails(Map<String, dynamic> member) async {
    if (!mounted) return;
    final lat = (member['last_lat'] as num?)?.toDouble();
    final lng = (member['last_lng'] as num?)?.toDouble();
    final name = member['pseudo']?.toString() ?? 'Membre';
    final hasPos = lat != null && lng != null;
    if (hasPos) _focusMember(member);

    // Bottom sheet loads address itself (no blocking dialog). The previous
    // showDialog + rootNavigator.pop path hung on many Android devices.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        return _MemberPlaceSheet(
          member: member,
          name: name,
          lat: lat,
          lng: lng,
          hasPos: hasPos,
          detailRow: _detailRow,
          onNavigate: () {
            Navigator.pop(ctx);
            openExternalMapsOrSnack(context, lat, lng, label: name);
          },
          onCenter: () {
            Navigator.pop(ctx);
            _focusMember(member);
          },
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.bleuFonce),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.gris,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(value, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _visibleMembers => _members.where((m) {
        if (m['visible_on_map'] == true) return true;
        // Backward-compat if API older / missing flag.
        return m['last_lat'] != null &&
            m['last_lng'] != null &&
            m['share_until'] != null;
      }).toList();

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showAppSnackBar(context, 'Indiquez un nom pour le cercle.', isError: true);
      return;
    }
    try {
      final created = await _api.post('/live-circles', {'name': name});
      final id = created['id']?.toString();
      await _refresh(selectId: id);
      if (mounted) {
        final code = created['invite_code']?.toString() ?? '';
        showAppSnackBar(
          context,
          code.isNotEmpty
              ? 'Cercle créé. Code : $code — partagez-le avec vos proches.'
              : 'Cercle créé. Partagez le code d\'invitation.',
        );
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
      final joined = await _api.post('/live-circles/join', {'code': code});
      _codeCtrl.clear();
      await _refresh(selectId: joined['id']?.toString());
      if (mounted) {
        showAppSnackBar(
          context,
          'Vous avez rejoint le cercle. Partagez votre GPS si vous voulez apparaître sur la carte.',
        );
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
      await _ensureMesh(sharing: true);
      await LocationService().updatePosition(
        pos.latitude,
        pos.longitude,
        force: true,
      );
      LocationService().startCircleLiveShare(
        heartbeat: const Duration(seconds: 8),
        distanceFilterMeters: 8,
      );
      try {
        await _api.patch('/live-circles/$id/share', {'hours': _shareHours});
        await _refresh(selectId: id);
        if (mounted) {
          showAppSnackBar(
            context,
            'Position partagée $_shareHours h (Internet + proximité locale).',
          );
        }
      } catch (_) {
        // Offline: keep local share + mesh so nearby family still sees you.
        final until =
            DateTime.now().add(Duration(hours: _shareHours)).toIso8601String();
        setState(() {
          _offlineMode = true;
          final idx = _circles.indexWhere((c) => c['id']?.toString() == id);
          if (idx >= 0) {
            _circles[idx] = {..._circles[idx], 'share_until': until};
          }
        });
        await _cache.enqueue('circle_share', {
          'circle_id': id,
          'hours': _shareHours,
        });
        if (mounted) {
          showAppSnackBar(
            context,
            'Hors ligne — partage local actif (Wi‑Fi / Bluetooth). Sync serveur au retour réseau.',
          );
        }
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

  Future<void> _stopSharing() async {
    final id = _selectedId;
    if (id == null) return;
    final me = context.read<AuthProvider>().user?['id']?.toString();
    try {
      LocationService().stopCircleLiveShare();
      await _mesh.setSharing(false);
      // Optimistic local clear so offline cache cannot keep « Partage actif ».
      if (!mounted) return;
      setState(() {
        _members = _members.map((m) {
          final copy = Map<String, dynamic>.from(m);
          final uid = copy['user_id']?.toString() ?? copy['id']?.toString();
          if (me != null && uid == me) {
            copy['share_until'] = null;
            copy['visible_on_map'] = false;
          }
          return copy;
        }).toList();
      });
      try {
        await _api.patch('/live-circles/$id/share', {'stop': true});
      } catch (_) {
        await _cache.enqueue('circle_share_stop', {'circle_id': id});
        final cached =
            await _cache.get('live_circle_members_$id', maxAgeSeconds: 86400);
        if (cached is List) {
          final patched = cached
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .map((m) {
            final uid = m['user_id']?.toString() ?? m['id']?.toString();
            if (me != null && uid == me) {
              m['share_until'] = null;
              m['visible_on_map'] = false;
            }
            return m;
          }).toList();
          await _cache.put('live_circle_members_$id', patched);
        }
      }
      await _refresh(selectId: id);
      if (mounted) {
        showAppSnackBar(context, 'Partage de position arrêté pour ce cercle.');
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, e, isError: true, fallback: 'Arrêt impossible');
      }
    }
  }

  Future<void> _leaveOrDelete() async {
    final id = _selectedId;
    final circle = _selectedCircle;
    if (id == null || circle == null) return;
    final owner = _isOwner;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(owner ? 'Supprimer le cercle ?' : 'Quitter le cercle ?'),
        content: Text(
          owner
              ? 'Tous les membres perdront l\'accès à « ${circle['name'] ?? 'ce cercle'} ».'
              : 'Vous ne verrez plus les positions de ce cercle.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(owner ? 'Supprimer' : 'Quitter'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      LocationService().stopCircleLiveShare();
      await _api.delete('/live-circles/$id/leave');
      _poll?.cancel();
      setState(() {
        _selectedId = null;
        _members = [];
      });
      await _refresh();
      if (mounted) {
        showAppSnackBar(
          context,
          owner ? 'Cercle supprimé.' : 'Vous avez quitté le cercle.',
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, e, isError: true, fallback: 'Action impossible');
      }
    }
  }

  String _shareStatusLabel() {
    final meshBit = _mesh.running
        ? ' · Proximité ${_mesh.peerCount} proche(s)'
        : '';
    final offlineBit = _offlineMode ? ' · hors ligne' : '';
    final until = _selectedCircle?['share_until']?.toString();
    if (until == null || until.isEmpty) {
      return 'Vous ne partagez pas encore votre position.$meshBit$offlineBit';
    }
    final t = DateTime.tryParse(until)?.toLocal();
    if (t == null) {
      return 'Vous ne partagez pas encore votre position.$meshBit$offlineBit';
    }
    if (t.isBefore(DateTime.now())) {
      return 'Partage expiré — relancez si besoin.$meshBit';
    }
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return 'Partage actif jusqu\'au ${t.day}/${t.month} $h:$m$meshBit$offlineBit';
  }

  Widget _namedPin(String name, {Color color = AppColors.vert}) {
    final label = name.trim().isEmpty ? 'Membre' : name.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 110),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.bleuFonce,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Icon(Icons.person_pin_circle, color: color, size: 34),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleMembers;
    final markers = visible.map((m) {
      final lat = (m['last_lat'] as num).toDouble();
      final lng = (m['last_lng'] as num).toDouble();
      final name = m['pseudo']?.toString() ?? 'Membre';
      return Marker(
        point: LatLng(lat, lng),
        width: 120,
        height: 72,
        alignment: Alignment.bottomCenter,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => _showMemberDetails(m),
            borderRadius: BorderRadius.circular(8),
            child: _namedPin(name),
          ),
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
                  'Partagez votre position avec vos proches en temps réel. '
                  'Avec Internet : via le serveur. Sans Internet : même Wi‑Fi '
                  'ou hotspot partagé (Android ↔ iOS). Créer / rejoindre ne '
                  'démarre pas le GPS — utilisez « Partager ma position ».',
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
                  final count = c['member_count'];
                  return ListTile(
                    selected: selected,
                    selectedTileColor: AppColors.bleu.withValues(alpha: 0.08),
                    title: Text(c['name']?.toString() ?? 'Cercle'),
                    subtitle: Text(
                      'Code : ${c['invite_code'] ?? '—'}'
                      '${role != null ? ' · $role' : ''}'
                      '${count != null ? ' · $count membre(s)' : ''}',
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
                  Text(
                    _shareStatusLabel(),
                    style: const TextStyle(fontSize: 12, color: AppColors.bleuFonce),
                  ),
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
                      _sharing
                          ? 'Partage…'
                          : (_amSharing
                              ? 'Prolonger / actualiser ma position'
                              : 'Partager ma position GPS'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  if (_amSharing) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _stopSharing,
                      icon: const Icon(Icons.location_off_outlined),
                      label: const Text('Arrêter le partage'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _leaveOrDelete,
                    icon: Icon(
                      _isOwner ? Icons.delete_outline : Icons.exit_to_app,
                      color: AppColors.rouge,
                      size: 18,
                    ),
                    label: Text(
                      _isOwner ? 'Supprimer le cercle' : 'Quitter le cercle',
                      style: const TextStyle(color: AppColors.rouge),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Membres',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.bleuFonce,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_members.isEmpty)
                    const Text(
                      'Aucun membre pour l\'instant.',
                      style: TextStyle(fontSize: 11, color: AppColors.gris),
                    )
                  else
                    ..._members.map((m) {
                      final onMap = m['visible_on_map'] == true ||
                          (m['last_lat'] != null && m['share_until'] != null);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        elevation: 0,
                        color: AppColors.bleu.withValues(alpha: 0.06),
                        child: ListTile(
                          dense: true,
                          enabled: true,
                          leading: Icon(
                            onMap ? Icons.location_on : Icons.person_outline,
                            color: onMap ? AppColors.vert : AppColors.gris,
                            size: 20,
                          ),
                          title: Text(m['pseudo']?.toString() ?? 'Membre'),
                          subtitle: Text(
                            onMap
                                ? 'Toucher pour détails · naviguer'
                                : 'Pas de partage GPS actif',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: onMap
                              ? IconButton(
                                  tooltip: 'Naviguer',
                                  icon: const Icon(Icons.directions, size: 20),
                                  onPressed: () {
                                    final la =
                                        (m['last_lat'] as num?)?.toDouble();
                                    final ln =
                                        (m['last_lng'] as num?)?.toDouble();
                                    openExternalMapsOrSnack(
                                      context,
                                      la,
                                      ln,
                                      label: m['pseudo']?.toString(),
                                    );
                                  },
                                )
                              : null,
                          onTap: () => _showMemberDetails(m),
                        ),
                      );
                    }),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 280,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: FlutterMap(
                        mapController: _mapCtrl,
                        options: MapOptions(
                          initialCenter: markers.isNotEmpty
                              ? markers.first.point
                              : const LatLng(-4.3217, 15.3125),
                          initialZoom: MapZoom.circleInitial,
                          // Map-level tap hit-test — reliable on Android where
                          // marker GestureDetectors inside ListView often fail.
                          onTap: _onMapTap,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.all,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.safealert.safealert',
                          ),
                          MarkerLayer(markers: markers),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    visible.isEmpty
                        ? 'Personne sur la carte — chaque membre doit appuyer sur « Partager ma position GPS ».'
                        : '${visible.length} position(s) · live ~3–5 s'
                            '${_offlineMode || _mesh.running ? ' (proximité locale)' : ''}'
                            ' · touchez un pin pour les détails',
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

/// Bottom sheet that resolves commune/quartier asynchronously (Android-safe).
class _MemberPlaceSheet extends StatefulWidget {
  final Map<String, dynamic> member;
  final String name;
  final double? lat;
  final double? lng;
  final bool hasPos;
  final Widget Function(IconData icon, String label, String value) detailRow;
  final VoidCallback onNavigate;
  final VoidCallback onCenter;

  const _MemberPlaceSheet({
    required this.member,
    required this.name,
    required this.lat,
    required this.lng,
    required this.hasPos,
    required this.detailRow,
    required this.onNavigate,
    required this.onCenter,
  });

  @override
  State<_MemberPlaceSheet> createState() => _MemberPlaceSheetState();
}

class _MemberPlaceSheetState extends State<_MemberPlaceSheet> {
  PlaceDetails? _place;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.hasPos) {
      _loading = true;
      _loadPlace();
    }
  }

  Future<void> _loadPlace() async {
    final la = widget.lat;
    final ln = widget.lng;
    if (la == null || ln == null) return;
    try {
      final place = await GeocodeService().reverseDetails(la, ln);
      if (!mounted) return;
      setState(() {
        _place = place;
        _loading = false;
        if (place == null) {
          _error = 'Adresse indisponible pour le moment';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Adresse indisponible pour le moment';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final seen = widget.member['last_seen_at']?.toString() ??
        widget.member['mesh_at']?.toString();
    final role = widget.member['role']?.toString();
    final mesh = widget.member['mesh'] == true;
    final la = widget.lat;
    final ln = widget.lng;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.bleuFonce,
              ),
            ),
            if (role != null && role.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Rôle : $role',
                style: const TextStyle(fontSize: 12, color: AppColors.gris),
              ),
            ],
            const SizedBox(height: 12),
            if (!widget.hasPos || la == null || ln == null)
              const Text(
                'Pas de position partagée pour le moment.',
                style: TextStyle(fontSize: 13, color: AppColors.gris),
              )
            else ...[
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else ...[
                widget.detailRow(
                  Icons.location_city_outlined,
                  'Commune',
                  _place?.commune ?? _error ?? 'Non déterminée',
                ),
                widget.detailRow(
                  Icons.holiday_village_outlined,
                  'Quartier',
                  _place?.quartier ??
                      (_place?.label.isNotEmpty == true
                          ? _place!.label
                          : (_error ?? 'Non déterminé')),
                ),
                if ((_place?.road ?? '').isNotEmpty)
                  widget.detailRow(
                    Icons.signpost_outlined,
                    'Rue',
                    _place!.road!,
                  ),
              ],
              widget.detailRow(
                Icons.my_location,
                'Coordonnées',
                '${la.toStringAsFixed(5)}, ${ln.toStringAsFixed(5)}',
              ),
              if (seen != null && seen.isNotEmpty)
                widget.detailRow(Icons.schedule, 'Dernière MAJ', seen),
              if (mesh)
                widget.detailRow(
                  Icons.wifi_tethering,
                  'Source',
                  'Réseau local (hors Internet)',
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: widget.onNavigate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.bleuFonce,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.directions, color: Colors.white),
                label: const Text(
                  'Naviguer vers cette position',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: widget.onCenter,
                icon: const Icon(Icons.center_focus_strong),
                label: const Text('Centrer sur la carte'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
