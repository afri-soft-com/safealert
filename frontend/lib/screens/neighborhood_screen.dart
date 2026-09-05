import 'package:flutter/material.dart';
import '../theme.dart';
import '../l10n/app_localizations.dart';
import '../providers/neighborhood_provider.dart';
import '../widgets/app_feedback.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';

class NeighborhoodScreen extends StatefulWidget {
  final VoidCallback onBack;
  final NeighborhoodProvider? provider;
  const NeighborhoodScreen({super.key, required this.onBack, this.provider});

  @override
  State<NeighborhoodScreen> createState() => _NeighborhoodScreenState();
}

class _NeighborhoodScreenState extends State<NeighborhoodScreen> {
  late final NeighborhoodProvider _nb;
  late final bool _ownsProvider;
  final _ctrl = TextEditingController();
  int _digestHour = 18;

  @override
  void initState() {
    super.initState();
    _ownsProvider = widget.provider == null;
    _nb = widget.provider ?? NeighborhoodProvider();
    _nb.addListener(_onNb);
    _nb.load();
  }

  void _onNb() {
    if (mounted) setState(() {});
  }

  Future<int?> _pickHour(int current) async {
    return showDialog<int>(
      context: context,
      builder: (ctx) {
        int draft = current;
        return AlertDialog(
          title: const Text('Heure du résumé', style: TextStyle(fontSize: 16)),
          content: DropdownButtonFormField<int>(
            value: draft,
            decoration: const InputDecoration(
              labelText: 'Heure (0–23)',
              border: OutlineInputBorder(),
            ),
            items: List.generate(
              24,
              (h) => DropdownMenuItem(
                value: h,
                child: Text('${h.toString().padLeft(2, '0')}h'),
              ),
            ),
            onChanged: (v) => draft = v ?? draft,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, draft),
              child: const Text('Valider'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _subscribe() async {
    if (_ctrl.text.trim().length < 2) return;
    try {
      await _nb.subscribe(_ctrl.text.trim(), _digestHour);
      _ctrl.clear();
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, e, isError: true, fallback: 'Impossible d\'enregistrer l\'abonnement.');
      }
    }
  }

  Future<void> _changeHour(Map<String, dynamic> sub) async {
    final current = (sub['digest_hour'] as num?)?.toInt() ?? 18;
    final picked = await _pickHour(current);
    if (picked == null || picked == current) return;
    try {
      await _nb.updateHour(sub['id'].toString(), picked);
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, e, isError: true, fallback: 'Impossible de modifier l\'heure.');
      }
    }
  }

  @override
  void dispose() {
    _nb.removeListener(_onNb);
    if (_ownsProvider) _nb.dispose();
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
            child: _nb.loading && _nb.subscriptions.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Recevez chaque jour un résumé des alertes de votre quartier.',
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
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        value: _digestHour,
                        decoration: const InputDecoration(
                          labelText: 'Heure du résumé quotidien',
                          border: OutlineInputBorder(),
                        ),
                        items: List.generate(
                          24,
                          (h) => DropdownMenuItem(
                            value: h,
                            child: Text('${h.toString().padLeft(2, '0')}h'),
                          ),
                        ),
                        onChanged: (v) => setState(() => _digestHour = v ?? 18),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _subscribe,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.vert),
                        child: const Text("S'abonner", style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(height: 16),
                      if (_nb.subscriptions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'Aucun quartier suivi. Ajoutez votre quartier pour recevoir le résumé quotidien.',
                            style: TextStyle(fontSize: 12, color: AppColors.gris),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        ..._nb.subscriptions.map((s) {
                          final hour = (s['digest_hour'] as num?)?.toInt() ?? 18;
                          return ListTile(
                            title: Text(s['quartier'] as String? ?? ''),
                            subtitle: Text('Résumé quotidien à ${hour}h'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Modifier l\'heure',
                                  icon: const Icon(Icons.schedule),
                                  onPressed: () => _changeHour(s),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () async {
                                    try {
                                      await _nb.unsubscribe(s['id'].toString());
                                    } catch (e) {
                                      if (mounted) {
                                        showAppSnackBar(
                                          context,
                                          e,
                                          isError: true,
                                          fallback: 'Impossible de se désabonner.',
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
