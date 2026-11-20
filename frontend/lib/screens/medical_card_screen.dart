import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';
import '../utils/network_error.dart';
import '../widgets/app_feedback.dart';

const kBloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

/// The user's own medical card: shown to trust contacts during an SOS only.
class MedicalCardScreen extends StatefulWidget {
  const MedicalCardScreen({super.key});

  @override
  State<MedicalCardScreen> createState() => _MedicalCardScreenState();
}

class _MedicalCardScreenState extends State<MedicalCardScreen> {
  final _api = ApiService();
  final _allergies = TextEditingController();
  final _conditions = TextEditingController();
  final _medications = TextEditingController();
  final _note = TextEditingController();
  String? _blood;
  bool _share = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_allergies, _conditions, _medications, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.get('/medical-card');
      final card = Map<String, dynamic>.from(res['card'] as Map? ?? {});
      setState(() {
        _blood = kBloodTypes.contains(card['blood_type']) ? card['blood_type'] as String : null;
        _allergies.text = (card['allergies'] ?? '').toString();
        _conditions.text = (card['conditions'] ?? '').toString();
        _medications.text = (card['medications'] ?? '').toString();
        _note.text = (card['emergency_note'] ?? '').toString();
        _share = card['share_on_sos'] != false;
      });
    } catch (e) {
      if (mounted) showAppSnackBar(context, userFacingError(e, fallback: 'Fiche indisponible.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _api.put('/medical-card', {
        'blood_type': _blood,
        'allergies': _allergies.text,
        'conditions': _conditions.text,
        'medications': _medications.text,
        'emergency_note': _note.text,
        'share_on_sos': _share,
      });
      if (mounted) showAppSnackBar(context, 'Fiche médicale enregistrée');
    } catch (e) {
      if (mounted) showAppSnackBar(context, userFacingError(e, fallback: 'Enregistrement impossible.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController c, String label, String hint) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          maxLines: 2,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fiche médicale')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Ces informations aident vos proches et les secours si vous déclenchez un SOS. '
                  'Elles ne sont visibles par vos contacts de confiance que pendant un SOS.',
                  style: TextStyle(fontSize: 12, color: AppColors.gris),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  value: _blood,
                  decoration: const InputDecoration(
                    labelText: 'Groupe sanguin',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Je ne sais pas')),
                    for (final b in kBloodTypes) DropdownMenuItem<String?>(value: b, child: Text(b)),
                  ],
                  onChanged: (v) => setState(() => _blood = v),
                ),
                const SizedBox(height: 12),
                _field(_allergies, 'Allergies', 'Ex. pénicilline, arachides'),
                _field(_conditions, 'Maladies / état de santé', 'Ex. diabète, asthme, grossesse'),
                _field(_medications, 'Traitements en cours', 'Ex. insuline, ventoline'),
                _field(_note, 'À savoir en urgence', 'Ex. personne à prévenir, médecin traitant'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _share,
                  onChanged: (v) => setState(() => _share = v),
                  title: const Text('Partager pendant un SOS', style: TextStyle(fontSize: 13)),
                  subtitle: const Text(
                    'Vos contacts de confiance et les leaders qui répondent à votre SOS peuvent la lire.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
                ),
              ],
            ),
    );
  }
}

/// Shows the medical card of someone whose SOS the user is answering.
/// Returns false when there is nothing to show (no card, not shared, no SOS).
Future<bool> showMedicalCardForSos(BuildContext context, String userId) async {
  Map<String, dynamic> card;
  try {
    final res = await ApiService().get('/medical-card/$userId');
    card = Map<String, dynamic>.from(res['card'] as Map? ?? {});
  } catch (e) {
    if (context.mounted) {
      showAppSnackBar(context, userFacingError(e, fallback: 'Aucune fiche médicale partagée.'));
    }
    return false;
  }
  if (!context.mounted) return false;
  final rows = <(String, String)>[
    ('Groupe sanguin', (card['blood_type'] ?? '').toString()),
    ('Allergies', (card['allergies'] ?? '').toString()),
    ('Santé', (card['conditions'] ?? '').toString()),
    ('Traitements', (card['medications'] ?? '').toString()),
    ('À savoir', (card['emergency_note'] ?? '').toString()),
  ].where((r) => r.$2.trim().isNotEmpty).toList();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('🩺 Fiche médicale — ${card['pseudo'] ?? ''}'.trim()),
      content: rows.isEmpty
          ? const Text('La fiche est vide.')
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${r.$1} : ', style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: r.$2),
                    ])),
                  ),
              ],
            ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
    ),
  );
  return true;
}
