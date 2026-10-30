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
  final void Function(String quartier)? onOpenDigest;
  const NeighborhoodScreen({
    super.key,
    required this.onBack,
    this.provider,
    this.onOpenDigest,
  });

  @override
  State<NeighborhoodScreen> createState() => _NeighborhoodScreenState();
}

class _NeighborhoodScreenState extends State<NeighborhoodScreen> {
  late final NeighborhoodProvider _nb;
  late final bool _ownsProvider;
  final _ctrl = TextEditingController();
  late int _digestHour;
  late int _digestMinute;

  @override
  void initState() {
    super.initState();
    _ownsProvider = widget.provider == null;
    _nb = widget.provider ?? NeighborhoodProvider();
    final next = NeighborhoodProvider.nextLocalSlot(minAhead: 5);
    _digestHour = next.hour;
    _digestMinute = next.minute;
    _nb.addListener(_onNb);
    _nb.load();
  }

  void _onNb() {
    if (mounted) setState(() {});
  }

  String get _timeLabel =>
      NeighborhoodProvider.formatHm(_digestHour, _digestMinute);

  Future<({int hour, int minute})?> _pickTime(int hour, int minute) async {
    return showDialog<({int hour, int minute})>(
      context: context,
      builder: (ctx) {
        var draftH = hour;
        var draftM = minute;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Heure du résumé', style: TextStyle(fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: draftH,
                    decoration: const InputDecoration(
                      labelText: 'Heure (téléphone)',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(
                      24,
                      (h) => DropdownMenuItem(
                        value: h,
                        child: Text('${h.toString().padLeft(2, '0')} h'),
                      ),
                    ),
                    onChanged: (v) => setLocal(() => draftH = v ?? draftH),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: draftM,
                    decoration: const InputDecoration(
                      labelText: 'Minutes',
                      border: OutlineInputBorder(),
                    ),
                    items: NeighborhoodProvider.digestMinuteSlots
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(':${m.toString().padLeft(2, '0')}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setLocal(() => draftM = v ?? draftM),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, (hour: draftH, minute: draftM)),
                  child: const Text('Valider'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _subscribe() async {
    final q = _ctrl.text.trim();
    if (q.length < 2) {
      showAppSnackBar(context, 'Indiquez un nom de quartier (min. 2 caractères).', isError: true);
      return;
    }
    try {
      await _nb.subscribe(q, _digestHour, _digestMinute);
      _ctrl.clear();
      if (mounted) {
        showAppSnackBar(
          context,
          'Abonné à « $q » — résumé quotidien à $_timeLabel (heure du téléphone).',
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, e, isError: true, fallback: 'Impossible d\'enregistrer l\'abonnement.');
      }
    }
  }

  Future<void> _changeTime(Map<String, dynamic> sub) async {
    final kHour = (sub['digest_hour'] as num?)?.toInt() ?? 18;
    final kMin = (sub['digest_minute'] as num?)?.toInt() ?? 0;
    final local = NeighborhoodProvider.kinshasaToLocal(kHour, kMin);
    final picked = await _pickTime(local.hour, NeighborhoodProvider.clampMinute(local.minute));
    if (picked == null) return;
    if (picked.hour == local.hour && picked.minute == local.minute) return;
    try {
      await _nb.updateTime(sub['id'].toString(), picked.hour, picked.minute);
      if (mounted) {
        showAppSnackBar(
          context,
          'Heure mise à jour : ${NeighborhoodProvider.formatHm(picked.hour, picked.minute)}',
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, e, isError: true, fallback: 'Impossible de modifier l\'heure.');
      }
    }
  }

  Future<void> _sendNow(Map<String, dynamic> sub) async {
    try {
      await _nb.sendNow(sub['id'].toString());
      if (mounted) {
        showAppSnackBar(context, 'Résumé envoyé — vérifiez vos notifications.');
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          e,
          isError: true,
          fallback: 'Envoi impossible. Activez les notifications push.',
        );
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
                        'Recevez chaque jour un résumé des alertes de votre quartier. '
                        'Choisissez l’heure sur votre téléphone (créneaux :00 / :15 / :30 / :45).',
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
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _digestHour,
                              decoration: const InputDecoration(
                                labelText: 'Heure',
                                border: OutlineInputBorder(),
                              ),
                              items: List.generate(
                                24,
                                (h) => DropdownMenuItem(
                                  value: h,
                                  child: Text('${h.toString().padLeft(2, '0')} h'),
                                ),
                              ),
                              onChanged: (v) => setState(() => _digestHour = v ?? 18),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _digestMinute,
                              decoration: const InputDecoration(
                                labelText: 'Minutes',
                                border: OutlineInputBorder(),
                              ),
                              items: NeighborhoodProvider.digestMinuteSlots
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(':${m.toString().padLeft(2, '0')}'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() => _digestMinute = v ?? 0),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Résumé prévu à $_timeLabel (heure du téléphone)',
                        style: const TextStyle(fontSize: 11, color: AppColors.gris),
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
                          final kHour = (s['digest_hour'] as num?)?.toInt() ?? 18;
                          final kMin = (s['digest_minute'] as num?)?.toInt() ?? 0;
                          final local = NeighborhoodProvider.kinshasaToLocal(kHour, kMin);
                          final label = NeighborhoodProvider.formatHm(
                            local.hour,
                            NeighborhoodProvider.clampMinute(local.minute),
                          );
                          final quartier = s['quartier'] as String? ?? '';
                          return ListTile(
                            title: Text(quartier),
                            subtitle: Text('Résumé quotidien à $label'),
                            onTap: widget.onOpenDigest != null && quartier.isNotEmpty
                                ? () => widget.onOpenDigest!(quartier)
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Voir le résumé',
                                  icon: const Icon(Icons.summarize_outlined),
                                  onPressed: widget.onOpenDigest != null && quartier.isNotEmpty
                                      ? () => widget.onOpenDigest!(quartier)
                                      : null,
                                ),
                                IconButton(
                                  tooltip: 'Recevoir maintenant',
                                  icon: const Icon(Icons.send_outlined),
                                  onPressed: () => _sendNow(s),
                                ),
                                IconButton(
                                  tooltip: 'Modifier l\'heure',
                                  icon: const Icon(Icons.schedule),
                                  onPressed: () => _changeTime(s),
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
