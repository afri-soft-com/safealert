import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../services/location_service.dart';
import '../services/refuge_service.dart';
import '../theme.dart';
import '../utils/open_maps.dart';
import '../utils/network_error.dart';
import '../widgets/app_feedback.dart';

/// Nearest safe places open to the public (hospitals, pharmacies, fuel
/// stations…), with directions. Leaders and agents can add places.
class RefugesScreen extends StatefulWidget {
  const RefugesScreen({super.key});

  @override
  State<RefugesScreen> createState() => _RefugesScreenState();
}

class _RefugesScreenState extends State<RefugesScreen> {
  final _service = RefugeService();
  List<Refuge> _items = const [];
  String? _category;
  double? _lat;
  double? _lng;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final resolved = await LocationService().getPositionWithSource(urgent: true);
    _lat = resolved.position?.latitude;
    _lng = resolved.position?.longitude;
    try {
      final list = await _service.fetch(lat: _lat, lng: _lng, category: _category);
      if (mounted) setState(() => _items = list);
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e, fallback: 'Liste indisponible.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addHere() async {
    if (_lat == null || _lng == null) {
      showAppSnackBar(context, 'Position GPS indisponible.', isError: true);
      return;
    }
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _AddRefugeDialog(lat: _lat!, lng: _lng!),
    );
    if (added == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = RefugeService.canEdit(context.watch<AuthProvider>().role);
    return Scaffold(
      appBar: AppBar(title: const Text('Lieux refuges')),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: _addHere,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Ajouter ici'),
            )
          : null,
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _chip(null, 'Tous'),
                for (final c in RefugeService.categories.entries) _chip(c.key, '${c.value.$1} ${c.value.$2}'),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _chip(String? value, String label) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: _category == value,
          onSelected: (_) {
            setState(() => _category = value);
            _load();
          },
        ),
      );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: AppColors.gris)));
    }
    if (_items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Aucun lieu refuge enregistré près de vous pour l\'instant. '
          'Les leaders de quartier peuvent en ajouter.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.gris),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final r = _items[i];
          final cat = RefugeService.categories[r.category] ?? ('📍', 'Autre');
          final subtitle = [
            cat.$2,
            if (r.distanceKm != null) RefugeService.formatDistance(r.distanceKm!),
            if (r.open24h) 'Ouvert 24h/24',
            if (r.address != null) r.address!,
          ].join(' · ');
          return ListTile(
            leading: Text(cat.$1, style: const TextStyle(fontSize: 24)),
            title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (r.phone != null)
                  IconButton(
                    tooltip: 'Appeler',
                    icon: const Icon(Icons.phone, color: AppColors.vert),
                    onPressed: () => launchUrl(Uri.parse('tel:${r.phone}')),
                  ),
                IconButton(
                  tooltip: 'Itinéraire',
                  icon: const Icon(Icons.directions, color: AppColors.bleu),
                  onPressed: () => openExternalMapsOrSnack(context, r.lat, r.lng, label: r.name),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AddRefugeDialog extends StatefulWidget {
  final double lat;
  final double lng;
  const _AddRefugeDialog({required this.lat, required this.lng});

  @override
  State<_AddRefugeDialog> createState() => _AddRefugeDialogState();
}

class _AddRefugeDialogState extends State<_AddRefugeDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  String _category = 'hospital';
  bool _open24h = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await RefugeService().create(
        name: _name.text,
        category: _category,
        lat: widget.lat,
        lng: widget.lng,
        phone: _phone.text,
        address: _address.text,
        open24h: _open24h,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAppSnackBar(context, userFacingError(e, fallback: 'Ajout impossible.'), isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter un lieu refuge'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('À votre position actuelle.', style: TextStyle(fontSize: 12, color: AppColors.gris)),
            const SizedBox(height: 10),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nom')),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final c in RefugeService.categories.entries)
                  DropdownMenuItem(value: c.key, child: Text('${c.value.$1} ${c.value.$2}')),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            TextField(controller: _address, decoration: const InputDecoration(labelText: 'Adresse (optionnel)')),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone (optionnel)'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _open24h,
              onChanged: (v) => setState(() => _open24h = v ?? false),
              title: const Text('Ouvert 24h/24', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        ElevatedButton(onPressed: _saving ? null : _save, child: const Text('Ajouter')),
      ],
    );
  }
}
