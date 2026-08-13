import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../l10n/app_localizations.dart';
import '../providers/trip_provider.dart';
import '../providers/contacts_provider.dart';
import '../services/share_helper.dart';
import '../services/location_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';

class TripScreen extends StatefulWidget {
  final VoidCallback onBack;
  final ValueChanged<String>? onNavigate;
  const TripScreen({super.key, required this.onBack, this.onNavigate});

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  final _destLabelCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _etaCtrl = TextEditingController(text: '30');
  final _followIdCtrl = TextEditingController();
  final Set<String> _selectedEscorts = {};
  Timer? _pingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<TripProvider>().fetchActive();
      await context.read<ContactsProvider>().fetchContacts();
      _maybeStartPing();
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
    _destLabelCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _etaCtrl.dispose();
    _followIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Latitude / longitude destination requises')),
      );
      return;
    }
    final pos = await LocationService().getCurrentPosition();
    final tripProv = context.read<TripProvider>();
    if (pos != null) {
      await tripProv.fetchRouteSuggestion(
        originLat: pos.latitude,
        originLng: pos.longitude,
        destLat: lat,
        destLng: lng,
      );
    }
    final trip = await tripProv.startTrip(
      destLat: lat,
      destLng: lng,
      destLabel: _destLabelCtrl.text.trim().isEmpty ? null : _destLabelCtrl.text.trim(),
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
                ] else ...[
                  const Text(
                    'Partagez votre trajet avec votre cercle de confiance. Une alerte part automatiquement si vous n\'arrivez pas à temps ou restez immobile trop longtemps.',
                    style: TextStyle(fontSize: 12, color: AppColors.gris),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _destLabelCtrl,
                    decoration: const InputDecoration(labelText: 'Destination (libellé)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _latCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Latitude destination', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _lngCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Longitude destination', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _etaCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'ETA (minutes)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 14),
                  const Text('Escorte (contacts inscrits)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.bleuFonce)),
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
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text('Démarrer — ${l10n.safeTrip}', style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
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
