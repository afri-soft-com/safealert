import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/trip_provider.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';

/// Carte live pour contacts qui suivent un trajet (mode escorte).
class EscortMapScreen extends StatefulWidget {
  final VoidCallback onBack;
  const EscortMapScreen({super.key, required this.onBack});

  @override
  State<EscortMapScreen> createState() => _EscortMapScreenState();
}

class _EscortMapScreenState extends State<EscortMapScreen> {
  final MapController _mapController = MapController();
  final _tripIdCtrl = TextEditingController();
  Timer? _pollTimer;
  String? _lastCenteredKey;
  bool _followLive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final trip = context.read<TripProvider>().followedTrip;
      if (trip != null) {
        _centerOnTrip(trip, force: true);
        _startPoll();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tripIdCtrl.dispose();
    super.dispose();
  }

  void _startPoll() {
    _pollTimer?.cancel();
    // Socket pushes trip_ping; polling is a safety net for missed events.
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final id = context.read<TripProvider>().followTripId;
      if (id != null) context.read<TripProvider>().fetchTrip(id);
    });
  }

  void _centerOnTrip(Map<String, dynamic> trip, {bool force = false}) {
    final lat = (trip['last_lat'] ?? trip['origin_lat']) as num?;
    final lng = (trip['last_lng'] ?? trip['origin_lng']) as num?;
    if (lat == null || lng == null) return;
    final key = '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
    if (!force && key == _lastCenteredKey) return;
    _lastCenteredKey = key;
    try {
      _mapController.move(LatLng(lat.toDouble(), lng.toDouble()), 15);
    } catch (_) {}
  }

  Future<void> _loadTrip() async {
    final id = _tripIdCtrl.text.trim();
    if (id.isEmpty) return;
    final trip = await context.read<TripProvider>().openEscortMap(id);
    if (!mounted) return;
    if (trip == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.read<TripProvider>().error ?? 'Trajet introuvable')),
      );
      return;
    }
    _centerOnTrip(trip, force: true);
    _startPoll();
  }

  String _fmtWhen(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  Widget _timeChip(String label, String? iso, {Color color = AppColors.bleu}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700)),
          Text(
            _fmtWhen(iso),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.bleuFonce),
          ),
        ],
      ),
    );
  }

  List<LatLng> _trackPoints(TripProvider prov, Map<String, dynamic> trip) {
    final track = prov.trackFor(trip);
    final pts = <LatLng>[];
    for (final p in track) {
      final la = (p['lat'] as num?)?.toDouble();
      final ln = (p['lng'] as num?)?.toDouble();
      if (la != null && ln != null) pts.add(LatLng(la, ln));
    }
    if (pts.isEmpty) {
      final oLat = trip['origin_lat'] as num?;
      final oLng = trip['origin_lng'] as num?;
      final lLat = trip['last_lat'] as num?;
      final lLng = trip['last_lng'] as num?;
      if (oLat != null && oLng != null) {
        pts.add(LatLng(oLat.toDouble(), oLng.toDouble()));
      }
      if (lLat != null &&
          lLng != null &&
          (pts.isEmpty ||
              (pts.last.latitude - lLat).abs() > 0.00001 ||
              (pts.last.longitude - lLng).abs() > 0.00001)) {
        pts.add(LatLng(lLat.toDouble(), lLng.toDouble()));
      }
    }
    return pts;
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TripProvider>();
    final trip = prov.followedTrip;
    final liveLat = (trip?['last_lat'] ?? trip?['origin_lat']) as num?;
    final liveLng = (trip?['last_lng'] ?? trip?['origin_lng']) as num?;
    final destLat = trip?['dest_lat'] as num?;
    final destLng = trip?['dest_lng'] as num?;
    final center = liveLat != null && liveLng != null
        ? LatLng(liveLat.toDouble(), liveLng.toDouble())
        : const LatLng(-4.3217, 15.3125);
    final track = trip != null ? _trackPoints(prov, trip) : const <LatLng>[];

    if (trip != null && _followLive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _centerOnTrip(trip);
      });
    }

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(title: 'Escorte — carte live', onBackTap: widget.onBack),
          if (trip == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Entrez l\'identifiant du trajet partagé pour suivre la position en direct.',
                    style: TextStyle(fontSize: 12, color: AppColors.gris),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tripIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ID trajet',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: prov.loading ? null : _loadTrip,
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.bleu),
                    child: prov.loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Suivre', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 15,
                      onPositionChanged: (camera, hasGesture) {
                        if (hasGesture && _followLive) {
                          setState(() => _followLive = false);
                        }
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.safealert.safealert',
                      ),
                      if (track.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: track,
                              color: AppColors.bleu.withValues(alpha: 0.85),
                              strokeWidth: 4.5,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          if (trip['origin_lat'] != null && trip['origin_lng'] != null)
                            Marker(
                              point: LatLng(
                                (trip['origin_lat'] as num).toDouble(),
                                (trip['origin_lng'] as num).toDouble(),
                              ),
                              width: 96,
                              height: 64,
                              alignment: Alignment.bottomCenter,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _timeChip('Départ', trip['created_at']?.toString()),
                                  const Icon(Icons.trip_origin, color: AppColors.bleu, size: 22),
                                ],
                              ),
                            ),
                          if (liveLat != null && liveLng != null)
                            Marker(
                              point: LatLng(liveLat.toDouble(), liveLng.toDouble()),
                              width: 48,
                              height: 48,
                              child: const Icon(Icons.navigation, color: AppColors.rouge, size: 38),
                            ),
                          if (destLat != null &&
                              destLng != null &&
                              trip['trip_mode']?.toString() != 'patrol')
                            Marker(
                              point: LatLng(destLat.toDouble(), destLng.toDouble()),
                              width: 110,
                              height: 64,
                              alignment: Alignment.bottomCenter,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _timeChip(
                                    trip['arrived_at'] != null ? 'Arrivée' : 'Prévu',
                                    (trip['arrived_at'] ?? trip['eta_at'])?.toString(),
                                    color: AppColors.vert,
                                  ),
                                  const Icon(Icons.flag, color: AppColors.vert, size: 32),
                                ],
                              ),
                            ),
                          if (trip['arrived_at'] != null &&
                              liveLat != null &&
                              liveLng != null &&
                              trip['trip_mode']?.toString() == 'patrol')
                            Marker(
                              point: LatLng(liveLat.toDouble(), liveLng.toDouble()),
                              width: 110,
                              height: 56,
                              alignment: Alignment.topCenter,
                              child: _timeChip(
                                'Arrivée',
                                trip['arrived_at']?.toString(),
                                color: AppColors.vert,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: Material(
                      elevation: 3,
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      child: IconButton(
                        tooltip: _followLive ? 'Suivi auto activé' : 'Recentrer sur la position',
                        onPressed: () {
                          setState(() => _followLive = true);
                          _centerOnTrip(trip, force: true);
                        },
                        icon: Icon(
                          Icons.my_location,
                          color: _followLive ? AppColors.bleu : AppColors.gris,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 16,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Vers ${trip['dest_label'] ?? 'destination'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.bleuFonce,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Départ : ${_fmtWhen(trip['created_at']?.toString())}'
                              '${trip['arrived_at'] != null ? ' · Arrivée : ${_fmtWhen(trip['arrived_at']?.toString())}' : ' · Arrivée prévue : ${_fmtWhen(trip['eta_at']?.toString())}'}',
                              style: const TextStyle(fontSize: 11, color: AppColors.bleuFonce, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'Statut : ${trip['status'] ?? '—'}'
                              '${track.length > 1 ? ' · ${track.length} points de tracé' : ''}',
                              style: const TextStyle(fontSize: 11, color: AppColors.gris),
                            ),
                            if (trip['abnormal_stop_at'] != null)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                  'Arrêt anormal détecté',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.rouge,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  context.read<TripProvider>().clearFollowedTrip();
                                  _pollTimer?.cancel();
                                  _lastCenteredKey = null;
                                },
                                child: const Text('Quitter le suivi'),
                              ),
                            ),
                          ],
                        ),
                      ),
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
