import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/app_feedback.dart';
import '../widgets/status_bar.dart';

/// Paywall / statut Premium (FR). Activation test si le serveur l'autorise.
class PremiumScreen extends StatefulWidget {
  final VoidCallback onBack;
  const PremiumScreen({super.key, required this.onBack});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  final _api = ApiService();
  bool _loading = true;
  bool _acting = false;
  String? _error;
  Map<String, dynamic>? _status;

  static const _benefitLabels = <String, String>{
    'trajets_illimites': 'Trajets sécurisés illimités',
    'eta_long': 'Suivi de trajet jusqu\'à 12 h',
    'contacts_elargis': 'Jusqu\'à 25 contacts de confiance',
    'historique_etendu': 'Historique étendu (100 alertes)',
    'sos_prioritaire': 'Priorité dans la file ops SOS',
  };

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

  Future<void> _tryCheckout() async {
    setState(() => _acting = true);
    try {
      final res = await _api.post('/premium/checkout', {});
      if (!mounted) return;
      final url = res['checkout_url'] as String?;
      if (url != null && url.isNotEmpty) {
        showAppSnackBar(context, 'Redirection paiement bientôt disponible');
      } else {
        showAppSnackBar(
          context,
          (res['message'] as String?) ??
              'Paiement en ligne bientôt disponible. Demandez un accès test ou contactez le support.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        e,
        isError: true,
        fallback: 'Checkout indisponible',
      );
    } finally {
      if (mounted) setState(() => _acting = false);
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
    final cdf = pricing?['monthly_cdf_approx'] ?? 5500;
    final benefits = (st?['benefits'] as List?)?.cast<String>() ??
        _benefitLabels.keys.toList();
    final until = st?['premium_until']?.toString();
    final testOk = st?['test_purchase_allowed'] == true;
    final checkoutOk = st?['checkout_available'] == true;

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
                                      : '$monthly USD / mois (~$cdf CDF) — ou $yearly USD / an',
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
                            final label = _benefitLabels[key] ?? key;
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
                            if (testOk)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _acting ? null : _activateTest,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.teal,
                                    foregroundColor: Colors.white,
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
                            if (testOk) const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _acting ? null : _tryCheckout,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.bleuFonce,
                                  side: const BorderSide(color: Color(0xFFDDDDDD)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  checkoutOk
                                      ? 'Payer avec Stripe'
                                      : 'Paiement en ligne (bientôt)',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Sans paiement configuré, utilisez l\'activation test '
                              '(environnement de test) ou demandez un accès à un administrateur.',
                              style: TextStyle(fontSize: 11, color: AppColors.gris),
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
