import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/annuaire_provider.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';
import '../widgets/nav_bar.dart';

class AnnuaireScreen extends StatefulWidget {
  final ValueChanged<String> onNavigate;
  final VoidCallback? onBack;
  const AnnuaireScreen({super.key, required this.onNavigate, this.onBack});

  @override
  State<AnnuaireScreen> createState() => _AnnuaireScreenState();
}

class _AnnuaireScreenState extends State<AnnuaireScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnnuaireProvider>().fetchNumbers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AnnuaireProvider>();
    final numbers = provider.numbers;

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(title: 'Annuaire d\'urgence', onBackTap: widget.onBack),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: provider.isOffline ? const Color(0xFFFFF3CD) : AppColors.vertClair,
                      border: Border.all(color: provider.isOffline ? AppColors.orange : AppColors.vert),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      provider.isOffline
                          ? '📶 Mode hors-ligne — Données mises en cache'
                          : '✅ Données à jour — Synchronisées avec le serveur',
                      style: TextStyle(fontSize: 11, color: provider.isOffline ? const Color(0xFF7A4F00) : AppColors.vert)),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: provider.loading
                        ? const Center(child: CircularProgressIndicator())
                        : numbers.isEmpty
                            ? const Center(child: Text('Aucun numéro d\'urgence disponible hors-ligne.',
                                style: TextStyle(fontSize: 12, color: AppColors.gris)))
                            : ListView.separated(
                                itemCount: numbers.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final s = numbers[i];
                                  final color = _colorForService(s['service_type'] as String?);
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.blanc,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFEEEEEE)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 44, height: 44,
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Center(child: Text(_iconForService(s['service_type'] as String?),
                                              style: const TextStyle(fontSize: 20))),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(s['service_name'] as String? ?? 'Service',
                                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
                                              Text(s['description'] as String? ?? '',
                                                  style: const TextStyle(fontSize: 11, color: AppColors.gris)),
                                            ],
                                          ),
                                        ),
                                        Flexible(
                                          child: GestureDetector(
                                            onTap: () {},
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: color,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                s['phone_number'] as String? ?? '',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
          NavBar(active: 'annuaire', onTap: widget.onNavigate),
        ],
      ),
    );
  }

  Color _colorForService(String? type) {
    switch (type) {
      case 'police': return AppColors.bleu;
      case 'hospital': return AppColors.rouge;
      case 'fire': return AppColors.orange;
      default: return AppColors.gris;
    }
  }

  String _iconForService(String? type) {
    switch (type) {
      case 'police': return '🚔';
      case 'hospital': return '🏥';
      case 'fire': return '🚒';
      default: return '📞';
    }
  }
}