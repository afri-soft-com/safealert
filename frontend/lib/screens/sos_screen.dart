import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../widgets/status_bar.dart';
import '../providers/incident_provider.dart';

class SOSScreen extends StatefulWidget {
  final VoidCallback onBack;
  const SOSScreen({super.key, required this.onBack});

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> {
  int _step = 0;
  bool _completed = false;
  bool _cancelling = false;
  static const _steps = [
    _StepData('📍', 'GPS localisé', AppColors.vert),
    _StepData('📲', 'Contacts alertés', AppColors.vert),
    _StepData('📡', 'Communauté notifiée', AppColors.vert),
    _StepData('🚨', 'Alerte transmise !', AppColors.rouge),
  ];

  Future<void> _sendSOS() async {
    if (_completed) return;
    setState(() => _step = 0);

    int i = 0;
    Timer.periodic(const Duration(milliseconds: 600), (timer) {
      i++;
      if (mounted) setState(() => _step = i);
      if (i >= 4) {
        timer.cancel();
        if (mounted) setState(() => _completed = true);
      }
    });

    try {
      await context.read<IncidentProvider>().triggerSOS(
        0, 0, type: 'sos',
      );
    } catch (_) {}
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
            child: Column(
              children: const [
                Text('ALERTE D\'URGENCE', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 2)),
                SizedBox(height: 4),
                Text('Bouton SOS', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: _completed ? AppColors.rougeLight : Colors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Spacer(flex: 1),
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
                          _step == 0 ? '🆘\nAPPUYER' : _completed ? '✅\nENVOYÉ !' : '⏳\nEnvoi...',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, height: 1.2),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(flex: 1),
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
                  if (_completed && !_cancelling) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          setState(() => _cancelling = true);
                          try {
                            await context.read<IncidentProvider>().cancelSOS();
                          } catch (_) {}
                          if (mounted) {
                            setState(() {
                              _cancelling = false;
                              _step = 0;
                              _completed = false;
                            });
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
                        label: Text(_cancelling ? 'Annulation...' : 'Annuler l\'alerte',
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('MODE DISCRET', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
                        SizedBox(height: 6),
                        Text('Pour déclencher sans afficher l\'app :', style: TextStyle(fontSize: 11, color: AppColors.gris)),
                        SizedBox(height: 4),
                        Text('Appuyer 3× sur le bouton Volume ↓', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.rouge)),
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
