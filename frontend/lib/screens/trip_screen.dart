import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../l10n/app_localizations.dart';
import '../providers/trip_provider.dart';
import '../providers/contacts_provider.dart';
import '../services/share_helper.dart';
import '../services/location_service.dart';
import '../services/geocode_service.dart';
import '../utils/location_format.dart';
import '../widgets/app_feedback.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';

const _defaultCenter = LatLng(-4.3217, 15.3125);

enum _MapPickTarget { origin, destination }

class TripScreen extends StatefulWidget {
  final VoidCallback onBack;
  final ValueChanged<String>? onNavigate;
  const TripScreen({super.key, required this.onBack, this.onNavigate});

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  final _originAddrCtrl = TextEditingController();
  final _destAddrCtrl = TextEditingController();
  final _originLatCtrl = TextEditingController();
  final _originLngCtrl = TextEditingController();
  final _destLatCtrl = TextEditingController();
  final _destLngCtrl = TextEditingController();
  final _etaCtrl = TextEditingController(text: '30');
  final _followIdCtrl = TextEditingController();
  final MapController _mapController = MapController();
  final Set<String> _selectedEscorts = {};
  Timer? _pingTimer;

  _MapPickTarget _pickTarget = _MapPickTarget.origin;
  LatLng? _origin;
  LatLng? _destination;
  LatLng _mapCenter = _defaultCenter;
  bool _locating = false;
  bool _geocoding = false;
  bool _showAdvancedCoords = false;
  bool _syncingFields = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final tripProv = context.read<TripProvider>();
      final contactsProv = context.read<ContactsProvider>();
      await tripProv.fetchActive();
      await contactsProv.fetchContacts();
      if (!mounted) return;
      _maybeStartPing();
      if (tripProv.activeTrip == null) {
        await _initMyLocationAsOrigin();
      }
    });
  }

  void _maybeStartPing() {
    _pingTimer?.cancel();
    final trip = context.read<TripProvider>().activeTrip;
    if (trip != null && trip['status'] == 'active') {
      _pingTimer = Timer.periodic(const Duration(seconds: 45), (_) {
        if (mounted) context.read<TripProvider>().ping();
      });
    }
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _originAddrCtrl.dispose();
    _destAddrCtrl.dispose();
    _originLatCtrl.dispose();
    _originLngCtrl.dispose();
    _destLatCtrl.dispose();
    _destLngCtrl.dispose();
    _etaCtrl.dispose();
    _followIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _initMyLocationAsOrigin() async {
    setState(() => _locating = true);
    final pos = await LocationService().getCurrentPosition();
    if (!mounted) return;
    if (pos != null) {
      final point = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _mapCenter = point;
        _locating = false;
      });
      try {
        _mapController.move(point, 14);
      } catch (_) {}
      await _applyPoint(_MapPickTarget.origin, point, reverseGeocode: true);
    } else {
      setState(() => _locating = false);
    }
  }

  void _writeCoordFields(_MapPickTarget target, LatLng point) {
    _syncingFields = true;
    final lat = point.latitude.toStringAsFixed(6);
    final lng = point.longitude.toStringAsFixed(6);
    if (target == _MapPickTarget.origin) {
      _originLatCtrl.text = lat;
      _originLngCtrl.text = lng;
    } else {
      _destLatCtrl.text = lat;
      _destLngCtrl.text = lng;
    }
    _syncingFields = false;
  }

  Future<void> _applyPoint(
    _MapPickTarget target,
    LatLng point, {
    bool reverseGeocode = true,
    String? addressOverride,
  }) async {
    setState(() {
      if (target == _MapPickTarget.origin) {
        _origin = point;
      } else {
        _destination = point;
      }
      _mapCenter = point;
    });
    _writeCoordFields(target, point);

    if (addressOverride != null && addressOverride.trim().isNotEmpty) {
      _syncingFields = true;
      if (target == _MapPickTarget.origin) {
        _originAddrCtrl.text = addressOverride.trim();
      } else {
        _destAddrCtrl.text = addressOverride.trim();
      }
      _syncingFields = false;
      if (mounted) setState(() {});
      return;
    }

    if (!reverseGeocode) {
      final fallback = LocationFormat.formatCoords(point.latitude, point.longitude);
      _syncingFields = true;
      if (target == _MapPickTarget.origin) {
        if (_originAddrCtrl.text.trim().isEmpty) _originAddrCtrl.text = fallback;
      } else {
        if (_destAddrCtrl.text.trim().isEmpty) _destAddrCtrl.text = fallback;
      }
      _syncingFields = false;
      if (mounted) setState(() {});
      return;
    }

    setState(() => _geocoding = true);
    final label = await GeocodeService().reverse(point.latitude, point.longitude);
    if (!mounted) return;
    final display = (label != null && label.isNotEmpty)
        ? label
        : LocationFormat.formatCoords(point.latitude, point.longitude);
    _syncingFields = true;
    if (target == _MapPickTarget.origin) {
      _originAddrCtrl.text = display;
    } else {
      _destAddrCtrl.text = display;
    }
    _syncingFields = false;
    setState(() => _geocoding = false);
  }

  Future<void> _useMyLocation(_MapPickTarget target) async {
    setState(() => _locating = true);
    final pos = await LocationService().getCurrentPosition();
    if (!mounted) return;
    setState(() => _locating = false);
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Position GPS indisponible. Activez la localisation.')),
      );
      return;
    }
    final point = LatLng(pos.latitude, pos.longitude);
    try {
      _mapController.move(point, 15);
    } catch (_) {}
    await _applyPoint(target, point, reverseGeocode: true);
  }

  Future<void> _onMapTap(TapPosition tapPosition, LatLng point) async {
    await _applyPoint(_pickTarget, point, reverseGeocode: true);
    // After setting origin, switch to destination for next tap (moto-taxi flow)
    if (_pickTarget == _MapPickTarget.origin && _destination == null) {
      setState(() => _pickTarget = _MapPickTarget.destination);
    }
  }

  Future<void> _resolveAddressField(_MapPickTarget target) async {
    final ctrl = target == _MapPickTarget.origin ? _originAddrCtrl : _destAddrCtrl;
    final text = ctrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _geocoding = true);
    final found = await GeocodeService().forward(text);
    if (!mounted) return;
    setState(() => _geocoding = false);

    if (found == null) {
      // Keep typed text; if coords already set, leave them; otherwise try parse coords only
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Adresse non trouvée — utilisez la carte ou les coordonnées GPS.',
          ),
        ),
      );
      return;
    }
    final point = LatLng(found.lat, found.lng);
    try {
      _mapController.move(point, 15);
    } catch (_) {}
    await _applyPoint(target, point, reverseGeocode: false, addressOverride: found.label);
  }

  void _applyManualCoords(_MapPickTarget target) {
    final latCtrl = target == _MapPickTarget.origin ? _originLatCtrl : _destLatCtrl;
    final lngCtrl = target == _MapPickTarget.origin ? _originLngCtrl : _destLngCtrl;
    final lat = double.tryParse(latCtrl.text.trim().replaceAll(',', '.'));
    final lng = double.tryParse(lngCtrl.text.trim().replaceAll(',', '.'));
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordonnées GPS invalides')),
      );
      return;
    }
    final point = LatLng(lat, lng);
    try {
      _mapController.move(point, 15);
    } catch (_) {}
    _applyPoint(target, point, reverseGeocode: true);
  }

  Future<void> _start() async {
    var origin = _origin;
    var dest = _destination;

    // Try resolve addresses if coords missing
    if (origin == null && _originAddrCtrl.text.trim().isNotEmpty) {
      await _resolveAddressField(_MapPickTarget.origin);
      origin = _origin;
    }
    if (dest == null && _destAddrCtrl.text.trim().isNotEmpty) {
      await _resolveAddressField(_MapPickTarget.destination);
      dest = _destination;
    }

    // Advanced coords fallback
    if (origin == null) {
      final lat = double.tryParse(_originLatCtrl.text.trim().replaceAll(',', '.'));
      final lng = double.tryParse(_originLngCtrl.text.trim().replaceAll(',', '.'));
      if (lat != null && lng != null) origin = LatLng(lat, lng);
    }
    if (dest == null) {
      final lat = double.tryParse(_destLatCtrl.text.trim().replaceAll(',', '.'));
      final lng = double.tryParse(_destLngCtrl.text.trim().replaceAll(',', '.'));
      if (lat != null && lng != null) dest = LatLng(lat, lng);
    }

    if (origin == null || dest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            origin == null && dest == null
                ? 'Définissez le point de départ et la destination (carte ou adresse).'
                : origin == null
                    ? 'Définissez le point de départ.'
                    : 'Définissez la destination.',
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    final tripProv = context.read<TripProvider>();
    await tripProv.fetchRouteSuggestion(
      originLat: origin.latitude,
      originLng: origin.longitude,
      destLat: dest.latitude,
      destLng: dest.longitude,
    );
    if (!mounted) return;
    final destLabel = _destAddrCtrl.text.trim().isEmpty
        ? null
        : _destAddrCtrl.text.trim();
    final trip = await tripProv.startTrip(
      originLat: origin.latitude,
      originLng: origin.longitude,
      destLat: dest.latitude,
      destLng: dest.longitude,
      destLabel: destLabel,
      etaMinutes: int.tryParse(_etaCtrl.text) ?? 30,
      escortContactIds: _selectedEscorts.isEmpty ? null : _selectedEscorts.toList(),
    );
    if (!mounted) return;
    if (trip == null) {
      final err = tripProv.error;
      showAppSnackBar(
        context,
        err ?? 'Une erreur est survenue. Réessayez.',
        isError: true,
        fallback: 'Impossible de démarrer le trajet.',
      );
      return;
    }
    _maybeStartPing();
    final share = tripProv.shareText;
    if (share != null && share.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Trajet démarré — partagez le lien de suivi'),
          action: SnackBarAction(
            label: 'Partager',
            onPressed: () => ShareHelper.shareText(share),
          ),
        ),
      );
    }
  }

  Future<void> _openEscortMap([String? tripId]) async {
    final id = tripId ?? _followIdCtrl.text.trim();
    if (id.isEmpty) {
      widget.onNavigate?.call('escort_map');
      return;
    }
    await context.read<TripProvider>().openEscortMap(id);
    widget.onNavigate?.call('escort_map');
  }

  String get _mapHint {
    if (_pickTarget == _MapPickTarget.origin) {
      return 'Appuyez sur la carte pour définir le départ';
    }
    return 'Appuyez sur la carte pour définir la destination';
  }

  Widget _buildPointField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required _MapPickTarget target,
    required Color accent,
    required IconData icon,
  }) {
    final selected = _pickTarget == target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? accent : AppColors.bleuFonce,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          onTap: () => setState(() => _pickTarget = target),
          onSubmitted: (_) => _resolveAddressField(target),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: selected ? accent.withValues(alpha: 0.06) : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: selected ? accent : const Color(0xFFE0E0E0),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: selected ? accent : const Color(0xFFE0E0E0),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accent, width: 1.5),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            prefixIcon: Icon(icon, size: 20, color: accent),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Ma position',
                  onPressed: _locating ? null : () => _useMyLocation(target),
                  icon: Icon(Icons.my_location, size: 22, color: accent),
                ),
                IconButton(
                  tooltip: 'Rechercher l\'adresse',
                  onPressed: _geocoding ? null : () => _resolveAddressField(target),
                  icon: Icon(Icons.search, size: 22, color: AppColors.gris),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateForm(List escortable, bool loading) {
    final markers = <Marker>[
      if (_origin != null)
        Marker(
          point: _origin!,
          width: 44,
          height: 44,
          child: const Icon(Icons.trip_origin, color: AppColors.bleu, size: 34),
        ),
      if (_destination != null)
        Marker(
          point: _destination!,
          width: 44,
          height: 44,
          child: const Icon(Icons.flag, color: AppColors.vert, size: 34),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Indiquez le point de départ et la destination sur la carte, par adresse, ou via « Ma position ». Une alerte part si vous n\'arrivez pas à temps.',
          style: TextStyle(fontSize: 12, color: AppColors.gris),
        ),
        const SizedBox(height: 12),
        // Map (style livraison / moto-taxi)
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 260,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _mapCenter,
                    initialZoom: 13,
                    onTap: _onMapTap,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.safealert.safealert',
                    ),
                    if (_origin != null && _destination != null)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [_origin!, _destination!],
                            color: AppColors.bleu.withValues(alpha: 0.55),
                            strokeWidth: 3,
                          ),
                        ],
                      ),
                    MarkerLayer(markers: markers),
                  ],
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  top: 10,
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            _pickTarget == _MapPickTarget.origin
                                ? Icons.trip_origin
                                : Icons.flag,
                            size: 16,
                            color: _pickTarget == _MapPickTarget.origin
                                ? AppColors.bleu
                                : AppColors.vert,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _mapHint,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.bleuFonce,
                              ),
                            ),
                          ),
                          if (_geocoding || _locating)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(24),
                    color: Colors.white,
                    child: IconButton(
                      tooltip: 'Ma position',
                      onPressed: _locating
                          ? null
                          : () => _useMyLocation(_pickTarget),
                      icon: const Icon(Icons.my_location, color: AppColors.bleu),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Sélecteur actif pour les touches carte
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const Text('Enlèvement / Départ'),
                selected: _pickTarget == _MapPickTarget.origin,
                onSelected: (_) => setState(() => _pickTarget = _MapPickTarget.origin),
                selectedColor: AppColors.bleu.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _pickTarget == _MapPickTarget.origin
                      ? AppColors.bleu
                      : AppColors.gris,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: const Text('Destination / Arrivée'),
                selected: _pickTarget == _MapPickTarget.destination,
                onSelected: (_) =>
                    setState(() => _pickTarget = _MapPickTarget.destination),
                selectedColor: AppColors.vert.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _pickTarget == _MapPickTarget.destination
                      ? AppColors.vert
                      : AppColors.gris,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildPointField(
          label: 'Enlèvement / Départ',
          hint: 'Adresse de départ, ou appuyez sur la carte',
          controller: _originAddrCtrl,
          target: _MapPickTarget.origin,
          accent: AppColors.bleu,
          icon: Icons.trip_origin,
        ),
        const SizedBox(height: 12),
        _buildPointField(
          label: 'Destination / Arrivée',
          hint: 'Adresse d\'arrivée, ou appuyez sur la carte',
          controller: _destAddrCtrl,
          target: _MapPickTarget.destination,
          accent: AppColors.vert,
          icon: Icons.flag,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _etaCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Durée estimée (minutes)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: _showAdvancedCoords,
            onExpansionChanged: (v) => setState(() => _showAdvancedCoords = v),
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Coordonnées GPS (optionnel)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.bleuFonce),
            ),
            subtitle: const Text(
              'Saisie manuelle latitude / longitude',
              style: TextStyle(fontSize: 11, color: AppColors.gris),
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _originLatCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      onChanged: (_) {
                        if (!_syncingFields) {}
                      },
                      decoration: const InputDecoration(
                        labelText: 'Lat. départ',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _originLngCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: 'Lng. départ',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Appliquer départ',
                    onPressed: () => _applyManualCoords(_MapPickTarget.origin),
                    icon: const Icon(Icons.check, color: AppColors.bleu),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _destLatCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: 'Lat. destination',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _destLngCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: 'Lng. destination',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Appliquer destination',
                    onPressed: () => _applyManualCoords(_MapPickTarget.destination),
                    icon: const Icon(Icons.check, color: AppColors.vert),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Escorte (contacts inscrits)',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.bleuFonce),
        ),
        const SizedBox(height: 6),
        if (escortable.isEmpty)
          const Text(
            'Aucun contact avec compte SafeAlert. Ils pourront suivre via l\'ID trajet.',
            style: TextStyle(fontSize: 11, color: AppColors.gris),
          )
        else
          ...escortable.map((c) {
            final uid = c['ref_user_id'].toString();
            final selected = _selectedEscorts.contains(uid);
            return CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: selected,
              title: Text(c['contact_name']?.toString() ?? 'Contact',
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(c['contact_phone']?.toString() ?? '',
                  style: const TextStyle(fontSize: 11, color: AppColors.gris)),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedEscorts.add(uid);
                  } else {
                    _selectedEscorts.remove(uid);
                  }
                });
              },
            );
          }),
        if (context.watch<TripProvider>().routeSuggestion != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.grisClair,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              context.watch<TripProvider>().routeSuggestion!['suggestion']?.toString() ?? '',
              style: const TextStyle(fontSize: 11, color: AppColors.bleuFonce),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: loading ? null : _start,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.bleu,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    'Démarrer — ${AppLocalizations.of(context).safeTrip}',
                    style: const TextStyle(color: Colors.white),
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final trip = context.watch<TripProvider>().activeTrip;
    final loading = context.watch<TripProvider>().loading;
    final contacts = context.watch<ContactsProvider>().contacts;
    final escortable = contacts.where((c) {
      final uid = c['ref_user_id']?.toString();
      return uid != null && uid.isNotEmpty;
    }).toList();

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(title: l10n.safeTrip, onBackTap: widget.onBack),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (trip != null && trip['status'] == 'active') ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.vertClair,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.vert),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Trajet en cours → ${trip['dest_label'] ?? 'Destination'}',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
                        const SizedBox(height: 6),
                        Text('ETA : ${trip['eta_at'] ?? '—'}',
                            style: const TextStyle(fontSize: 12, color: AppColors.gris)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'ID : ${trip['id']}',
                                style: const TextStyle(fontSize: 11, color: AppColors.gris),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copier ID',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: '${trip['id']}'));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('ID trajet copié')),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 18),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  await context.read<TripProvider>().arrive();
                                  _pingTimer?.cancel();
                                },
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.vert),
                                child: Text(l10n.imSafe),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () async {
                                await context.read<TripProvider>().cancel();
                                _pingTimer?.cancel();
                              },
                              child: const Text('Annuler'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _openEscortMap(trip['id']?.toString()),
                          icon: const Icon(Icons.map_outlined, size: 18),
                          label: const Text('Carte escorte live'),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final tp = context.read<TripProvider>();
                                  var text = tp.shareText;
                                  if (text == null || text.isEmpty) {
                                    await tp.createShareLink();
                                    text = tp.shareText;
                                  }
                                  if (text != null) await ShareHelper.shareText(text);
                                },
                                icon: const Icon(Icons.share, size: 16),
                                label: const Text('Partager', style: TextStyle(fontSize: 11)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final tp = context.read<TripProvider>();
                                  var text = tp.shareText;
                                  if (text == null || text.isEmpty) {
                                    await tp.createShareLink();
                                    text = tp.shareText;
                                  }
                                  if (text != null) await ShareHelper.shareWhatsApp(text);
                                },
                                icon: const Icon(Icons.chat, size: 16),
                                label: const Text('WhatsApp', style: TextStyle(fontSize: 11)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.vert,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else
                  _buildCreateForm(escortable, loading),
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 8),
                const Text('Suivre un trajet (escorte)',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
                const SizedBox(height: 8),
                TextField(
                  controller: _followIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ID trajet à suivre',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _openEscortMap(),
                  icon: const Icon(Icons.route, size: 18),
                  label: const Text('Ouvrir la carte escorte'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
