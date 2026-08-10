import 'package:flutter/material.dart';
import '../theme.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';

class NeighborhoodScreen extends StatefulWidget {
  final VoidCallback onBack;
  const NeighborhoodScreen({super.key, required this.onBack});

  @override
  State<NeighborhoodScreen> createState() => _NeighborhoodScreenState();
}

class _NeighborhoodScreenState extends State<NeighborhoodScreen> {
  final _api = ApiService();
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _subs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('/neighborhood');
      _subs = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {
      _subs = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _subscribe() async {
    if (_ctrl.text.trim().length < 2) return;
    try {
      await _api.post('/neighborhood/subscribe', {
        'quartier': _ctrl.text.trim(),
        'digest_hour': 18,
      });
      _ctrl.clear();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(title: l10n.neighborhood, onBackTap: widget.onBack),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Recevez un digest push quotidien des incidents dans votre quartier.',
                        style: TextStyle(fontSize: 12, color: AppColors.gris),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _ctrl,
                        decoration: const InputDecoration(
                          labelText: 'Quartier (ex. Gombe, Limete)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _subscribe,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.vert),
                        child: const Text("S'abonner", style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(height: 16),
                      ..._subs.map((s) => ListTile(
                            title: Text(s['quartier'] as String? ?? ''),
                            subtitle: Text('Digest à ${s['digest_hour']}h'),
                            trailing: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () async {
                                await _api.delete('/neighborhood/${s['id']}');
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
