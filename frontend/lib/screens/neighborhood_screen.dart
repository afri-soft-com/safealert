import 'package:flutter/material.dart';
import '../theme.dart';
import '../l10n/app_localizations.dart';
import '../providers/neighborhood_provider.dart';
import '../services/location_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';

class NeighborhoodScreen extends StatefulWidget {
  final VoidCallback onBack;
  final NeighborhoodProvider? provider;
  final void Function(String quartier, {String? subscriptionId, String? city})? onOpenDigest;
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
  final _quartierCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  late int _digestHour;
  late int _digestMinute;
  int _radiusM = 5000;
  bool _subscribing = false;

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
    final q = _quartierCtrl.text.trim();
    if (q.length < 2) {
      showAppSnackBar(context, 'Indiquez un nom de quartier (min. 2 caractères).', isError: true);
      return;
    }
    setState(() => _subscribing = true);
    final loc = LocationService();
    try {
      // Same cascade as SOS: GPS → dernière position connue → cache local.
      final resolved = await loc.getPositionWithSource();
      final pos = resolved.position;
      if (pos == null) {
        final why = await loc.diagnoseLocationBlocker();
        if (!mounted) return;
        final openSettings = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Position indisponible', style: TextStyle(fontSize: 16)),
            content: Text(why, style: const TextStyle(fontSize: 13)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('OK')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Réglages'),
              ),
            ],
          ),
        );
        if (openSettings == true) {
          final foreverBlocked = why.contains('bloquée');
          if (foreverBlocked) {
            await loc.openAppLocationSettings();
          } else {
            await loc.openSystemLocationSettings();
          }
        }
        return;
      }
      final created = await _nb.subscribe(
        quartier: q,
        digestHour: _digestHour,
        digestMinute: _digestMinute,
        city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        lat: pos.latitude,
        lng: pos.longitude,
        radiusM: _radiusM,
      );
      final city = (created['city'] as String?)?.trim();
      if (city != null && city.isNotEmpty && _cityCtrl.text.trim().isEmpty) {
        _cityCtrl.text = city;
      }
      _quartierCtrl.clear();
      if (mounted) {
        final place = [
          q,
          if (city != null && city.isNotEmpty) city,
          NeighborhoodProvider.formatRadius(_radiusM),
        ].join(' · ');
        final srcHint = resolved.source == 'gps'
            ? ''
            : ' (position récente)';
        showAppSnackBar(
          context,
          'Abonné à $place — résumé à $_timeLabel$srcHint',
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, e, isError: true, fallback: 'Impossible d\'enregistrer l\'abonnement.');
      }
    } finally {
      if (mounted) setState(() => _subscribing = false);
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

  void _openDigest(Map<String, dynamic> sub) {
    final quartier = sub['quartier'] as String? ?? '';
    if (quartier.isEmpty || widget.onOpenDigest == null) return;
    widget.onOpenDigest!(
      quartier,
      subscriptionId: sub['id']?.toString(),
      city: sub['city'] as String?,
    );
  }

  @override
  void dispose() {
    _nb.removeListener(_onNb);
    if (_ownsProvider) _nb.dispose();
    _quartierCtrl.dispose();
    _cityCtrl.dispose();
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
                        'Résumé quotidien des alertes autour de votre position GPS '
                        '(évite les homonymes entre villes). Créneaux :00 / :15 / :30 / :45.',
                        style: TextStyle(fontSize: 12, color: AppColors.gris),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _quartierCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Quartier (ex. Gombe)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _cityCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Ville / commune (optionnel)',
                          hintText: 'Détectée via GPS si vide',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Rayon de veille',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final m in NeighborhoodProvider.radiusPresetsM)
                            ChoiceChip(
                              label: Text(NeighborhoodProvider.formatRadius(m)),
                              selected: _radiusM == m,
                              onSelected: (_) => setState(() => _radiusM = m),
                            ),
                        ],
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
                        'Résumé prévu à $_timeLabel · rayon ${NeighborhoodProvider.formatRadius(_radiusM)}',
                        style: const TextStyle(fontSize: 11, color: AppColors.gris),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _subscribing ? null : _subscribe,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.vert),
                        child: Text(
                          _subscribing ? 'Localisation…' : "S'abonner (GPS)",
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_nb.subscriptions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'Aucun quartier suivi. Ajoutez votre quartier près de vous.',
                            style: TextStyle(fontSize: 12, color: AppColors.gris),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        ..._nb.subscriptions.map((s) {
                          final kHour = (s['digest_hour'] as num?)?.toInt() ?? 18;
                          final kMin = (s['digest_minute'] as num?)?.toInt() ?? 0;
                          final local = NeighborhoodProvider.kinshasaToLocal(kHour, kMin);
                          final when = NeighborhoodProvider.formatHm(
                            local.hour,
                            NeighborhoodProvider.clampMinute(local.minute),
                          );
                          final quartier = s['quartier'] as String? ?? '';
                          final city = (s['city'] as String?)?.trim();
                          final radius = (s['radius_m'] as num?)?.toInt() ?? 5000;
                          final title = [
                            quartier,
                            if (city != null && city.isNotEmpty) city,
                          ].join(' · ');
                          return ListTile(
                            title: Text(title),
                            subtitle: Text(
                              'Résumé à $when · ${NeighborhoodProvider.formatRadius(radius)}',
                            ),
                            onTap: () => _openDigest(s),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Voir le résumé',
                                  icon: const Icon(Icons.summarize_outlined),
                                  onPressed: () => _openDigest(s),
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
