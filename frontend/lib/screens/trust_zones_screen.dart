import 'package:flutter/material.dart';
import '../theme.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';

class TrustZonesScreen extends StatefulWidget {
  final VoidCallback onBack;
  const TrustZonesScreen({super.key, required this.onBack});

  @override
  State<TrustZonesScreen> createState() => _TrustZonesScreenState();
}

class _TrustZonesScreenState extends State<TrustZonesScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _zones = [];
  bool _loading = true;
  String _type = 'home';
  final _labelCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('/trust-zones');
      _zones = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {
      _zones = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final pos = await LocationService().getCurrentPosition();
    if (pos == null || _labelCtrl.text.trim().isEmpty) return;
    try {
      await _api.post('/trust-zones', {
        'label': _labelCtrl.text.trim(),
        'zone_type': _type,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'radius_m': 200,
      });
      _labelCtrl.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
                        'Alertes ciblées lorsque un SOS survient près de votre domicile, travail ou école.',
                        style: TextStyle(fontSize: 12, color: AppColors.gris),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _labelCtrl,
                        decoration: const InputDecoration(labelText: 'Libellé', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _type,
                        decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Type'),
                        items: const [
                          DropdownMenuItem(value: 'home', child: Text('Domicile')),
                          DropdownMenuItem(value: 'work', child: Text('Travail')),
                          DropdownMenuItem(value: 'school', child: Text('École')),
                          DropdownMenuItem(value: 'custom', child: Text('Autre')),
                        ],
                        onChanged: (v) => setState(() => _type = v ?? 'home'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _add,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.bleu),
                        child: const Text('Ajouter ici (GPS actuel)', style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(height: 16),
                      ..._zones.map((z) => ListTile(
                            title: Text(z['label'] as String? ?? ''),
                            subtitle: Text('${z['zone_type']} · ${z['radius_m']} m'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.rouge),
                              onPressed: () async {
                                await _api.delete('/trust-zones/${z['id']}');
                                await _load();
                              },
                            ),
                          )),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
