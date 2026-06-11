import 'package:flutter/material.dart';
import '../theme.dart';
import '../data/safety_tips.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';
import '../widgets/nav_bar.dart';

class SafetyScreen extends StatelessWidget {
  final ValueChanged<String> onNavigate;
  const SafetyScreen({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          const TopBar(title: 'Conseils de sécurité'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    border: Border.all(color: AppColors.orange),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('📶 Disponible hors-ligne — Conseils toujours accessibles sans connexion',
                    style: TextStyle(fontSize: 11, color: Color(0xFF7A4F00))),
                ),
                const SizedBox(height: 14),
                ...safetyCategories.map((cat) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.blanc,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cat.color.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(cat.icon, style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 10),
                            Text(cat.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cat.color)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...cat.tips.asMap().entries.map((entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${entry.key + 1}.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cat.color)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(entry.value, style: const TextStyle(fontSize: 11, color: AppColors.bleuFonce, height: 1.3)),
                              ),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                )),
              ],
            ),
          ),
          NavBar(active: 'home', onTap: onNavigate),
        ],
      ),
    );
  }
}