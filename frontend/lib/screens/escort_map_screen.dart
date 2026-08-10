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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final trip = context.read<TripProvider>().followedTrip;
      if (trip != null) {
        _centerOnTrip(trip);
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
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final id = context.read<TripProvider>().followTripId;
      if (id != null) context.read<TripProvider>().fetchTrip(id);
    });
  }

  void _centerOnTrip(Map<String, dynamic> trip) {
    final lat = (trip['last_lat'] ?? trip['origin_lat']) as num?;
    final lng = (trip['last_lng'] ?? trip['origin_lng']) as num?;
    if (lat == null || lng == null) return;
    try {
      _mapController.move(LatLng(lat.toDouble(), lng.toDouble()), 14);
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
    _centerOnTrip(trip);
    _startPoll();
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
                    options: MapOptions(initialCenter: center, initialZoom: 14),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.safealert.safealert',
                      ),
                      MarkerLayer(
                        markers: [
                          if (liveLat != null && liveLng != null)
                            Marker(
                              point: LatLng(liveLat.toDouble(), liveLng.toDouble()),
                              width: 44,
                              height: 44,
                              child: const Icon(Icons.navigation, color: AppColors.bleu, size: 36),
                            ),
                          if (destLat != null && destLng != null)
                            Marker(
                              point: LatLng(destLat.toDouble(), destLng.toDouble()),
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.flag, color: AppColors.vert, size: 32),
                            ),
                        ],
                      ),
                    ],
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
                              'Statut : ${trip['status'] ?? '—'} · ETA ${trip['eta_at'] ?? '—'}',
                              style: const TextStyle(fontSize: 11, color: AppColors.gris),
                            ),
                            if (trip['abnormal_stop_at'] != null)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                  'Arrêt anormal détecté',
                                  style: TextStyle(fontSize: 11, color: AppColors.rouge, fontWeight: FontWeight.w600),
                                ),
                              ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  context.read<TripProvider>().clearFollowedTrip();
                                  _pollTimer?.cancel();
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
