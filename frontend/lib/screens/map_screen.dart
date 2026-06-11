import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/incident_provider.dart';
import '../services/location_service.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';
import '../widgets/nav_bar.dart';

/// Kinshasa — centre par défaut si GPS indisponible
const _defaultCenter = LatLng(-4.3217, 15.3125);

class MapScreen extends StatefulWidget {
  final ValueChanged<String> onNavigate;
  final bool isGuest;
  const MapScreen({super.key, required this.onNavigate, this.isGuest = false});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  dynamic _selectedId;
  final MapController _mapController = MapController();
  LatLng _center = _defaultCenter;
  bool _locating = false;
  String _typeFilter = 'all';
  int _hoursFilter = 24;

  static const _typeOptions = {
    'all': 'Tous types',
    'agression': 'Agression',
    'vol': 'Vol',
    'suspect': 'Suspect',
    'incendie': 'Incendie',
    'autre': 'Autre',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initLocation();
      if (mounted) await _loadIncidents();
    });
  }

  Future<void> _loadIncidents() async {
    await context.read<IncidentProvider>().fetchIncidents(
      hours: _hoursFilter,
      incidentType: _typeFilter,
    );
  }

  Future<void> _initLocation() async {
    setState(() => _locating = true);
    final pos = await LocationService().getCurrentPosition();
    if (pos != null && mounted) {
      setState(() {
        _center = LatLng(pos.latitude, pos.longitude);
        _locating = false;
      });
      _mapController.move(_center, 14);
    } else if (mounted) {
      setState(() => _locating = false);
    }
  }

  void _requireLogin(String action) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connexion requise', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text('Connectez-vous pour $action.', style: const TextStyle(fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onNavigate('login');
            },
            child: const Text('Se connecter'),
          ),
        ],
      ),
    );
  }

  void _showReportSheet() async {
    if (widget.isGuest) {
      _requireLogin('signaler un incident');
      return;
    }
    final descCtrl = TextEditingController();
    final pos = await LocationService().getCurrentPosition();
    final lat = pos?.latitude ?? _center.latitude;
    final lng = pos?.longitude ?? _center.longitude;

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String selectedType = 'agression';
        bool anonymous = false;
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20, right: 20, top: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Signaler un incident', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
                const SizedBox(height: 6),
                Text('Position : ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                    style: const TextStyle(fontSize: 10, color: AppColors.gris)),
                const SizedBox(height: 14),
                const Text('Type d\'incident', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.gris)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  items: ['agression', 'vol', 'suspect', 'incendie', 'autre'].map((t) =>
                    DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13))),
                  ).toList(),
                  onChanged: (v) => setSheetState(() => selectedType = v ?? 'agression'),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Description (optionnelle)',
                    hintStyle: const TextStyle(fontSize: 12, color: AppColors.gris),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.all(12),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      height: 24,
                      child: Checkbox(
                        value: anonymous,
                        onChanged: (v) => setSheetState(() => anonymous = v ?? false),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text('Signaler anonymement', style: TextStyle(fontSize: 11, color: AppColors.gris)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await context.read<IncidentProvider>().reportIncident(
                        lat, lng, selectedType,
                        description: descCtrl.text.isEmpty ? null : descCtrl.text,
                        anonymous: anonymous,
                      );
                      await _loadIncidents();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.rouge,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('ENVOYER LE SIGNALEMENT', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showVerifySheet(dynamic id) {
    if (widget.isGuest) {
      _requireLogin('confirmer un signalement');
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Confirmer ce signalement ?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
            const SizedBox(height: 6),
            const Text('Votre confirmation aide la communauté à évaluer la situation.',
                style: TextStyle(fontSize: 11, color: AppColors.gris)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Non', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final provider = context.read<IncidentProvider>();
                      final ok = await provider.verifyIncident(id);
                      if (mounted && !ok && provider.lastVerifyError != null) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(provider.lastVerifyError!, style: const TextStyle(fontSize: 11)),
                          backgroundColor: AppColors.orange,
                        ));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.vert,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('✅ Confirmer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  List<Marker> _buildMarkers(List<Map<String, dynamic>> incidents) {
    return incidents.map((inc) {
      final lat = (inc['lat'] as num?)?.toDouble();
      final lng = (inc['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      final id = inc['id'];
      final color = _colorForSeverity(inc['severity'] as String?);
      final verifications = inc['verified_by'] ?? inc['verifications'] ?? 0;
      final selected = _selectedId == id;

      return Marker(
        point: LatLng(lat, lng),
        width: 36,
        height: 36,
        child: GestureDetector(
          onTap: () => setState(() => _selectedId = selected ? null : id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: Colors.white, width: selected ? 3 : 2),
              boxShadow: selected ? [BoxShadow(color: color, blurRadius: 6)] : null,
            ),
            child: Center(
              child: Text('$verifications',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );
    }).whereType<Marker>().toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IncidentProvider>();
    final incidents = provider.incidents;
    final selected = _selectedId != null
        ? incidents.cast<Map<String, dynamic>?>().firstWhere(
            (i) => i?['id'] == _selectedId, orElse: () => null)
        : null;

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          const TopBar(title: 'Carte des incidents'),
          if (widget.isGuest)
            Container(
              width: double.infinity,
              color: AppColors.grisClair,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: const Text('Mode invité — connectez-vous pour signaler ou confirmer',
                  style: TextStyle(fontSize: 10, color: AppColors.gris, fontWeight: FontWeight.w600)),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _badge('Danger', AppColors.rouge),
                              const SizedBox(width: 6),
                              _badge('Vigilance', AppColors.orange),
                              const SizedBox(width: 6),
                              _badge('Sûr', AppColors.vert),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (provider.isOffline)
                        const Text('📶', style: TextStyle(fontSize: 12))
                      else
                        Text('${incidents.length} alertes',
                            style: const TextStyle(fontSize: 10, color: AppColors.gris), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _typeFilter,
                          isDense: true,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                          items: _typeOptions.entries.map((e) =>
                            DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 11))),
                          ).toList(),
                          onChanged: (v) async {
                            setState(() => _typeFilter = v ?? 'all');
                            await _loadIncidents();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      _periodChip('24h', 24),
                      const SizedBox(width: 4),
                      _periodChip('7j', 168),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: provider.loading && incidents.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              children: [
                                FlutterMap(
                                  mapController: _mapController,
                                  options: MapOptions(
                                    initialCenter: _center,
                                    initialZoom: 13,
                                    onTap: (_, __) => setState(() => _selectedId = null),
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName: 'com.safealert.app',
                                    ),
                                    MarkerLayer(markers: _buildMarkers(incidents)),
                                  ],
                                ),
                                if (_locating)
                                  const Positioned(
                                    top: 8, right: 8,
                                    child: SizedBox(
                                      width: 20, height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                Positioned(
                                  bottom: 8, left: 0, right: 0,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text('© OpenStreetMap — ${_hoursFilter == 24 ? '24h' : '7 jours'}',
                                          style: const TextStyle(color: Colors.white, fontSize: 9)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  if (selected != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _colorForSeverity(selected['severity'] as String?).withValues(alpha: 0.1),
                        border: Border.all(color: _colorForSeverity(selected['severity'] as String?), width: 1.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(selected['incident_type'] as String? ?? 'Incident',
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                            color: _colorForSeverity(selected['severity'] as String?))),
                                    if (selected['description'] != null)
                                      Text(selected['description'] as String,
                                          style: const TextStyle(fontSize: 11, color: AppColors.gris)),
                                    Text('✅ ${selected['verified_by'] ?? selected['verifications'] ?? 0} confirmations',
                                        style: const TextStyle(fontSize: 10, color: AppColors.gris)),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => setState(() => _selectedId = null),
                                child: const Icon(Icons.close, color: AppColors.gris, size: 18),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _showVerifySheet(selected['id']),
                              icon: const Icon(Icons.verified, size: 16),
                              label: const Text('Confirmer ce signalement',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.vert,
                                side: const BorderSide(color: AppColors.vert),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else
                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 8),
                      child: Text('Touchez un marqueur pour voir les détails',
                          style: TextStyle(fontSize: 11, color: AppColors.gris)),
                    ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _showReportSheet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.rouge,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        widget.isGuest ? '🔒 Se connecter pour signaler' : '📍 Signaler un incident ici',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          NavBar(active: 'map', onTap: widget.onNavigate),
        ],
      ),
    );
  }

  Widget _periodChip(String label, int hours) {
    final selected = _hoursFilter == hours;
    return GestureDetector(
      onTap: () async {
        setState(() => _hoursFilter = hours);
        await _loadIncidents();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.bleuFonce.withValues(alpha: 0.12) : AppColors.grisClair,
          border: Border.all(color: selected ? AppColors.bleuFonce : const Color(0xFFDDDDDD)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: selected ? AppColors.bleuFonce : AppColors.gris,
        )),
      ),
    );
  }

  Color _colorForSeverity(String? severity) {
    switch (severity) {
      case 'alert':
      case 'danger':
        return AppColors.rouge;
      case 'vigilance':
        return AppColors.orange;
      case 'safe':
        return AppColors.vert;
      default:
        return AppColors.orange;
    }
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
