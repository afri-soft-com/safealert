import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../l10n/app_localizations.dart';
import '../widgets/status_bar.dart';
import '../providers/incident_provider.dart';
import '../providers/checkin_provider.dart';

class SOSScreen extends StatefulWidget {
  final VoidCallback onBack;
  const SOSScreen({super.key, required this.onBack});

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> {
  int _step = 0;
  bool _completed = false;
  bool _failed = false;
  bool _cancelling = false;
  bool _checkingIn = false;
  String? _incidentId;
  String? _statusMsg;
  Timer? _progressTimer;
  Timer? _liveTimer;
  static const _steps = [
    _StepData('📍', 'GPS localisé', AppColors.vert),
    _StepData('📲', 'Contacts alertés', AppColors.vert),
    _StepData('📡', 'Communauté notifiée', AppColors.vert),
    _StepData('🚨', 'Alerte transmise !', AppColors.rouge),
  ];

  @override
  void dispose() {
    _progressTimer?.cancel();
    _liveTimer?.cancel();
    super.dispose();
  }

  void _startLiveStatus() {
    _liveTimer?.cancel();
    if (_incidentId == null) return;
    _liveTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || _incidentId == null) return;
      context.read<IncidentProvider>().publishLiveStatus(_incidentId!);
    });
    context.read<IncidentProvider>().publishLiveStatus(_incidentId!);
  }

  Future<void> _sendSOS() async {
    if (_completed) return;
    _progressTimer?.cancel();
    setState(() {
      _step = 0;
      _failed = false;
      _completed = false;
      _statusMsg = null;
      _incidentId = null;
    });

    final result = await context.read<IncidentProvider>().triggerSOS(
      0, 0, type: 'sos',
    );

    if (!mounted) return;
    if (result == null) {
      setState(() => _failed = true);
      return;
    }

    final incident = result['incident'] as Map<String, dynamic>?;
    _incidentId = incident?['id'] as String?;

    int i = 0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      i++;
      if (mounted) setState(() => _step = i);
      if (i >= 4) {
        timer.cancel();
        if (mounted) {
          setState(() => _completed = true);
          _startLiveStatus();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          Container(
            width: double.infinity,
            color: AppColors.rouge,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: widget.onBack,
                  child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ALERTE D\'URGENCE', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 2)),
                      SizedBox(height: 4),
                      Text('Bouton SOS', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: _completed ? AppColors.rougeLight : Colors.white,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                children: [
                  if (_failed)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3CD),
                        border: Border.all(color: AppColors.orange),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '📶 Pas de connexion — L\'alerte n\'a pas pu être envoyée. Réessayez dès que le réseau est disponible.',
                        style: TextStyle(fontSize: 11, color: Color(0xFF7A4F00)),
                      ),
                    ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: _sendSOS,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 160, height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _step > 0 ? AppColors.rougeDark : AppColors.rouge,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.rouge.withValues(alpha: _step > 0 ? 0.2 : 0.15),
                            blurRadius: _step > 0 ? 32 : 12,
                            spreadRadius: _step > 0 ? 16 : 0,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _failed
                              ? '📶\nRÉESSAYER'
                              : _step == 0
                                  ? '🆘\nAPPUYER'
                                  : _completed
                                      ? '✅\nENVOYÉ !'
                                      : '⏳\nEnvoi...',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, height: 1.2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...List.generate(_steps.length, (i) {
                    final s = _steps[i];
                    final done = _step > i;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: done ? s.color.withValues(alpha: 0.1) : const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: done ? s.color : const Color(0xFFEEEEEE)),
                      ),
                      child: Row(
                        children: [
                          Text(done ? '✅' : s.icon, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(s.label, style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600,
                              color: done ? s.color : AppColors.gris,
                            ), overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (_statusMsg != null) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.vertClair,
                        border: Border.all(color: AppColors.vert),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_statusMsg!, style: const TextStyle(fontSize: 12, color: AppColors.vert)),
                    ),
                  ],
                  if (_completed && !_cancelling) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _checkingIn
                            ? null
                            : () async {
                                setState(() => _checkingIn = true);
                                final ok = await context.read<CheckInProvider>().imSafe(incidentId: _incidentId);
                                _liveTimer?.cancel();
                                if (mounted) {
                                  setState(() {
                                    _checkingIn = false;
                                    if (ok) {
                                      _statusMsg = AppLocalizations.of(context).checkInSent;
                                      _completed = false;
                                      _step = 0;
                                      _incidentId = null;
                                    }
                                  });
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.vert,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: _checkingIn
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.verified_user, size: 18),
                        label: Text(AppLocalizations.of(context).imSafe,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          setState(() => _cancelling = true);
                          try {
                            final ok = await context.read<IncidentProvider>().cancelSOS();
                            _liveTimer?.cancel();
                            if (mounted) {
                              setState(() {
                                _cancelling = false;
                                _step = 0;
                                _completed = false;
                                _incidentId = null;
                                _statusMsg = ok
                                    ? AppLocalizations.of(context).falseAlarm
                                    : 'Annulation impossible';
                              });
                            }
                          } catch (_) {
                            if (mounted) setState(() => _cancelling = false);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: _cancelling
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.cancel, size: 18),
                        label: Text(_cancelling ? 'Annulation...' : 'Fausse alerte — annuler',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.grisClair,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MODE DISCRET', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
                        SizedBox(height: 6),
                        Text('Pour déclencher sans afficher l\'app :', style: TextStyle(fontSize: 11, color: AppColors.gris)),
                        SizedBox(height: 4),
                        Text('• 3× Volume ↓  ·  Secouer le téléphone  ·  Raccourci SOS',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.rouge)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: widget.onBack,
                    child: const Text('← Retour à l\'accueil', style: TextStyle(color: AppColors.gris, fontSize: 12)),
                  ),
                ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepData {
  final String icon;
  final String label;
  final Color color;
  const _StepData(this.icon, this.label, this.color);
}
