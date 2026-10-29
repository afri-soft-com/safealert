import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/safety_ping_provider.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';

/// Contrôle planifié « Tu es OK ? »
class SafetyPingScreen extends StatefulWidget {
  final VoidCallback onBack;
  const SafetyPingScreen({super.key, required this.onBack});

  @override
  State<SafetyPingScreen> createState() => _SafetyPingScreenState();
}

class _SafetyPingScreenState extends State<SafetyPingScreen> {
  int _inMinutes = 5;
  int _window = 5;
  bool _notifyGroups = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SafetyPingProvider>().fetchActive();
      context.read<SafetyPingProvider>().fetchHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SafetyPingProvider>();
    final active = p.active;

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(title: 'Je rentre / Tu es OK ?', onBackTap: widget.onBack),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.vert.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.vert.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '1) À l’heure choisie → vous seul recevez « Tu es OK ? ».\n'
                    '2) Si vous ne répondez pas pendant le délai → contacts de confiance '
                    '(push + SMS), et groupes si l’option est activée '
                    '(push + SMS + onglet Alertes).\n'
                    'Exemple : 5 min + 5 min = alerte proches après ~10 min.',
                    style: TextStyle(fontSize: 12, color: AppColors.bleuFonce, height: 1.4),
                  ),
                ),
                const SizedBox(height: 16),
                if (active != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.orange),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Contrôle en cours',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(height: 6),
                        Text(
                          'Rappel prévu : ${active['due_at'] ?? '—'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  final ok = await p.confirmOk();
                                  if (context.mounted && ok) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Merci — tout va bien !')),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.vert,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Je suis OK'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => p.cancel(),
                              child: const Text('Annuler'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Text('Dans combien de temps ?', style: TextStyle(fontSize: 12, color: AppColors.gris)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      // 1–2 min = QA ; 5–15 = tests ; 30+ = usage réel
                      for (final m in [1, 2, 5, 10, 15, 30, 60, 120, 180])
                        ChoiceChip(
                          label: Text(m < 60 ? '$m min' : '${m ~/ 60} h'),
                          selected: _inMinutes == m,
                          onSelected: (_) => setState(() => _inMinutes = m),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Délai pour répondre après le rappel', style: TextStyle(fontSize: 12, color: AppColors.gris)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final m in [1, 2, 5, 10, 15, 30])
                        ChoiceChip(
                          label: Text('$m min'),
                          selected: _window == m,
                          onSelected: (_) => setState(() => _window = m),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      'Alerte proches / groupes dans ~${_inMinutes + _window} min si pas de réponse.',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.orange),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Prévenir aussi mes groupes', style: TextStyle(fontSize: 13)),
                    subtitle: const Text(
                      'Sinon seuls les contacts de confiance sont alertés',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _notifyGroups,
                    onChanged: (v) => setState(() => _notifyGroups = v),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: p.loading
                          ? null
                          : () async {
                              final ok = await p.schedule(
                                inMinutes: _inMinutes,
                                windowMinutes: _window,
                                notifyGroups: _notifyGroups,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(ok
                                        ? 'Contrôle planifié — alerte proches dans ~${_inMinutes + _window} min sans réponse'
                                        : (p.error ?? 'Erreur')),
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.bleuFonce,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Planifier le contrôle'),
                    ),
                  ),
                ],
                if (p.error != null) ...[
                  const SizedBox(height: 8),
                  Text(p.error!, style: const TextStyle(color: AppColors.rouge, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
