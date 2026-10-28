import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/app_feedback.dart';
import '../widgets/status_bar.dart';

/// Paywall / statut Premium (FR). Mobile Money (MP/AM) + activation test.
class PremiumScreen extends StatefulWidget {
  final VoidCallback onBack;
  const PremiumScreen({super.key, required this.onBack});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  final _api = ApiService();
  final _phoneCtrl = TextEditingController();
  bool _loading = true;
  bool _acting = false;
  bool _polling = false;
  String? _error;
  Map<String, dynamic>? _status;
  String _plan = 'monthly';
  String _telecom = 'MP';

  static const _benefitLabels = <String, String>{
    'trajets_illimites': 'Trajets sécurisés illimités',
    'eta_long': 'Suivi de trajet jusqu\'à 12 h',
    'contacts_elargis': 'Jusqu\'à 25 contacts de confiance',
    'historique_etendu': 'Historique étendu (100 alertes)',
    'sos_prioritaire': 'Priorité dans la file ops SOS',
    'sos_mediation': 'Médiation SOS avec un opérateur',
    'live_circles': 'Cercles famille en direct (jusqu\'à 5)',
    'live_circles_max': 'Cercles famille en direct (jusqu\'à 5)',
  };

  String _benefitLabel(String key) {
    final known = _benefitLabels[key];
    if (known != null) return known;
    // Humanize unknown keys (e.g. sos_mediation → Sos mediation).
    final cleaned = key.replaceAll('_', ' ').trim();
    if (cleaned.isEmpty) return key;
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get('/premium/status');
      if (!mounted) return;
      setState(() {
        _status = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _activateTest() async {
    setState(() => _acting = true);
    try {
      await _api.post('/premium/grant', {'days': 30});
      if (!mounted) return;
      showAppSnackBar(context, 'Premium activé pour 30 jours (test)');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        e,
        isError: true,
        fallback: 'Impossible d\'activer Premium',
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  /// RDC prefixes → Mobile Money operator (national 2 digits).
  static const _prefixTelecom = <String, String>{
    '81': 'MP', '82': 'MP', '83': 'MP',
    '97': 'AM', '98': 'AM', '99': 'AM',
    '80': 'OM', '84': 'OM', '85': 'OM', '89': 'OM',
    '90': 'AF', '91': 'AF',
  };
  static const _telecomLabel = <String, String>{
    'MP': 'M-Pesa (Vodacom)',
    'AM': 'Airtel Money',
    'OM': 'Orange Money',
    'AF': 'AfriMoney',
  };
  static const _telecomHint = <String, String>{
    'MP': '081 / 082 / 083',
    'AM': '097 / 098 / 099',
    'OM': '080 / 084 / 085 / 089',
    'AF': '090 / 091',
  };

  /// Normalize to 243XXXXXXXXX (12 digits) or null if incomplete.
  String? _normalizeMmDigits(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('243') && digits.length > 12) {
      digits = digits.substring(0, 12);
    }
    if (digits.startsWith('0') && digits.length == 10) {
      digits = '243${digits.substring(1)}';
    } else if (digits.length == 9) {
      digits = '243$digits';
    }
    if (!RegExp(r'^243\d{9}$').hasMatch(digits)) return null;
    return digits;
  }

  int _nationalDigitCount(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('243')) digits = digits.substring(3);
    if (digits.startsWith('0')) digits = digits.substring(1);
    return digits.length.clamp(0, 9);
  }

  String? _detectTelecomFromPhone(String raw) {
    final digits = _normalizeMmDigits(raw);
    if (digits == null || digits.length < 5) return null;
    return _prefixTelecom[digits.substring(3, 5)];
  }

  /// RDC Mobile Money: format + opérateur cohérent avec le préfixe.
  String? _validateMmPhone(String raw) {
    final digits = _normalizeMmDigits(raw);
    if (digits == null) {
      final n = _nationalDigitCount(raw);
      if (n == 0) return 'Entrez votre numéro Mobile Money';
      return 'Numéro incomplet ($n/9 chiffres après +243). Exemple : ${_telecomHint[_telecom] ?? '0970…'}';
    }
    final detected = _detectTelecomFromPhone(raw);
    if (detected == null) {
      return 'Préfixe inconnu. ${_telecomLabel[_telecom]} utilise ${_telecomHint[_telecom]}.';
    }
    if (detected != _telecom) {
      return 'Ce numéro est ${_telecomLabel[detected]}, pas ${_telecomLabel[_telecom]}. '
          'Sélectionnez ${_telecomLabel[detected]} ou saisissez un numéro ${_telecomHint[_telecom]}.';
    }
    return null;
  }

  void _onPhoneChanged(String _) {
    final detected = _detectTelecomFromPhone(_phoneCtrl.text);
    if (detected != null &&
        detected != _telecom &&
        (detected == 'MP' || detected == 'AM' || detected == 'OM')) {
      setState(() => _telecom = detected);
    } else {
      setState(() {});
    }
  }

  Future<void> _payMobileMoney() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      showAppSnackBar(context, 'Entrez votre numéro Mobile Money', isError: true);
      return;
    }
    final phoneErr = _validateMmPhone(phone);
    if (phoneErr != null) {
      showAppSnackBar(context, phoneErr, isError: true);
      return;
    }
    setState(() => _acting = true);
    try {
      final intent = await _api.post('/premium/mobile-money', {
        'plan': _plan,
        'phone': phone,
        'telecom': _telecom,
      });
      if (!mounted) return;
      final id = intent['id']?.toString();
      showAppSnackBar(
        context,
        (intent['message'] as String?) ??
            'Confirmez le paiement sur votre téléphone (USSD / PIN).',
      );
      if (id != null && id.isNotEmpty) {
        await _pollPayment(id);
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        e,
        isError: true,
        fallback: 'Paiement Mobile Money indisponible',
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _pollPayment(String intentId) async {
    if (_polling) return;
    setState(() => _polling = true);
    try {
      for (var i = 0; i < 24; i++) {
        await Future<void>.delayed(const Duration(seconds: 5));
        if (!mounted) return;
        final res = await _api.get('/premium/payments/$intentId');
        final status = (res['status'] as String?)?.toLowerCase() ?? '';
        if (status == 'completed') {
          showAppSnackBar(context, 'Premium activé — merci !');
          await _load();
          return;
        }
        if (status == 'failed' || status == 'cancelled') {
          showAppSnackBar(
            context,
            (res['message'] as String?) ??
                (res['failure_reason'] as String?) ??
                'Paiement échoué',
            isError: true,
          );
          return;
        }
      }
      if (mounted) {
        showAppSnackBar(
          context,
          'Paiement en cours — rouvrez Premium dans quelques minutes.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        e,
        isError: true,
        fallback: 'Suivi du paiement interrompu',
      );
    } finally {
      if (mounted) setState(() => _polling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _status;
    final active = st?['active'] == true;
    final enabled = st?['feature_enabled'] == true;
    final pricing = (st?['pricing'] as Map?)?.cast<String, dynamic>();
    final monthly = pricing?['monthly_usd'] ?? 2;
    final yearly = pricing?['yearly_usd'] ?? 20;
    final cdf = pricing?['monthly_cdf'] ??
        pricing?['monthly_cdf_approx'] ??
        5500;
    final yearlyCdf = pricing?['yearly_cdf'] ??
        pricing?['yearly_cdf_approx'] ??
        55000;
    final benefits = (st?['benefits'] as List?)?.cast<String>() ??
        _benefitLabels.keys.toList();
    final until = st?['premium_until']?.toString();
    final testOk = st?['test_purchase_allowed'] == true;
    final mmOk = st?['mobile_money_available'] == true ||
        st?['afriSoftPayHubEnabled'] == true;

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          Container(
            width: double.infinity,
            color: AppColors.bleuFonce,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: widget.onBack,
                  child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'SafeAlert Premium',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center,
                                  style: const TextStyle(color: AppColors.gris)),
                              const SizedBox(height: 12),
                              TextButton(onPressed: _load, child: const Text('Réessayer')),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.vertClair
                                  : AppColors.blanc,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: active
                                    ? AppColors.vert
                                    : const Color(0xFFEEEEEE),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  active
                                      ? 'Votre abonnement Premium est actif'
                                      : enabled
                                          ? 'Passez à Premium'
                                          : 'Premium bientôt disponible',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.bleuFonce,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  active && until != null
                                      ? 'Valable jusqu\'au ${_fmtDate(until)}'
                                      : '$monthly USD / mois (~$cdf CDF) — ou $yearly USD / an (~$yearlyCdf CDF)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.gris,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Avantages Premium',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.gris,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...benefits.map((key) {
                            final label = _benefitLabel(key);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.check_circle,
                                      size: 18, color: AppColors.teal),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      label,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.bleuFonce,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 20),
                          if (!active && enabled) ...[
                            if (mmOk) ...[
                              const Text(
                                'Payer par Mobile Money',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.gris,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(
                                    value: 'monthly',
                                    label: Text('Mensuel'),
                                  ),
                                  ButtonSegment(
                                    value: 'yearly',
                                    label: Text('Annuel'),
                                  ),
                                ],
                                selected: {_plan},
                                onSelectionChanged: _acting
                                    ? null
                                    : (s) => setState(() => _plan = s.first),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _TelecomChip(
                                    label: 'M-Pesa',
                                    selected: _telecom == 'MP',
                                    recommended: true,
                                    onTap: () => setState(() => _telecom = 'MP'),
                                  ),
                                  _TelecomChip(
                                    label: 'Airtel Money',
                                    selected: _telecom == 'AM',
                                    recommended: true,
                                    onTap: () => setState(() => _telecom = 'AM'),
                                  ),
                                  _TelecomChip(
                                    label: 'Orange Money',
                                    selected: _telecom == 'OM',
                                    recommended: false,
                                    onTap: () => setState(() => _telecom = 'OM'),
                                  ),
                                ],
                              ),
                              if (_telecom == 'OM') ...[
                                const SizedBox(height: 8),
                                const Text(
                                  'Orange Money échoue souvent. Choisissez M-Pesa ou Airtel Money.',
                                  style: TextStyle(fontSize: 11, color: AppColors.rouge),
                                ),
                              ],
                              const SizedBox(height: 12),
                              TextField(
                                controller: _phoneCtrl,
                                keyboardType: TextInputType.phone,
                                onChanged: _onPhoneChanged,
                                decoration: InputDecoration(
                                  labelText: 'Numéro Mobile Money',
                                  hintText: _telecom == 'MP'
                                      ? '081… / 082… (Vodacom)'
                                      : _telecom == 'OM'
                                          ? '084… / 089… (Orange)'
                                          : '097… / 099… (Airtel)',
                                  helperText: () {
                                    final n = _nationalDigitCount(_phoneCtrl.text);
                                    final err = _phoneCtrl.text.trim().isEmpty
                                        ? null
                                        : _validateMmPhone(_phoneCtrl.text.trim());
                                    if (err != null) return err;
                                    return '$n/9 — ${_telecomLabel[_telecom]} '
                                        '(${_telecomHint[_telecom]})';
                                  }(),
                                  helperMaxLines: 3,
                                  helperStyle: TextStyle(
                                    fontSize: 11,
                                    color: (_phoneCtrl.text.trim().isNotEmpty &&
                                            _validateMmPhone(
                                                    _phoneCtrl.text.trim()) !=
                                                null)
                                        ? AppColors.rouge
                                        : AppColors.gris,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: (_acting ||
                                          _polling ||
                                          _validateMmPhone(_phoneCtrl.text.trim()) !=
                                              null)
                                      ? null
                                      : _payMobileMoney,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.teal,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: Text(
                                    _polling
                                        ? 'En attente de confirmation…'
                                        : _acting
                                            ? 'Envoi…'
                                            : 'Payer ${_plan == 'yearly' ? yearlyCdf : cdf} CDF',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Préférez M-Pesa ou Airtel Money. Confirmez ensuite '
                                'sur votre téléphone (USSD / notification).',
                                style: TextStyle(fontSize: 11, color: AppColors.gris),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (testOk)
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: _acting ? null : _activateTest,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.bleuFonce,
                                    side: const BorderSide(color: Color(0xFFDDDDDD)),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: Text(
                                    _acting
                                        ? 'Activation…'
                                        : 'Activer Premium (test — 30 jours)',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ),
                            if (!mmOk && !testOk)
                              const Text(
                                'Paiement bientôt disponible. Demandez un accès à un administrateur.',
                                style: TextStyle(fontSize: 12, color: AppColors.gris),
                              ),
                          ],
                          if (!enabled)
                            const Text(
                              'L\'abonnement n\'est pas encore ouvert sur ce serveur. '
                              'Les fonctions actuelles restent disponibles selon les limites habituelles.',
                              style: TextStyle(fontSize: 12, color: AppColors.gris),
                            ),
                          if (active)
                            const Text(
                              'Merci de soutenir SafeAlert. Vos avantages sont déjà actifs.',
                              style: TextStyle(fontSize: 12, color: AppColors.gris),
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/'
          '${d.year}';
    } catch (_) {
      return iso;
    }
  }
}

class _TelecomChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  const _TelecomChip({
    required this.label,
    required this.selected,
    required this.recommended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(
        recommended ? '$label ★' : label,
        style: TextStyle(
          fontSize: 12,
          color: selected ? Colors.white : AppColors.bleuFonce,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.teal,
      backgroundColor: const Color(0xFFF5F7F7),
    );
  }
}
