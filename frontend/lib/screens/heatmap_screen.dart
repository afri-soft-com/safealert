import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/incident_provider.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';
import '../widgets/nav_bar.dart';

class HeatmapScreen extends StatefulWidget {
  final ValueChanged<String> onNavigate;
  final VoidCallback? onBack;
  const HeatmapScreen({super.key, required this.onNavigate, this.onBack});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<IncidentProvider>().fetchHeatmap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final zones = context.watch<IncidentProvider>().heatmap;
    final maxVal = zones.isEmpty ? 1 : zones.map((z) => (z['total'] as int? ?? 0)).reduce((a, b) => a > b ? a : b);

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(title: 'Carte de chaleur — Densité incidents', onBackTap: widget.onBack),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.grisClair,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _dot(AppColors.vert, 'Faible'),
                        const SizedBox(width: 12),
                        _dot(AppColors.orange, 'Moyen'),
                        const SizedBox(width: 12),
                        _dot(AppColors.rouge, 'Élevé'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: zones.isEmpty
                        ? const Center(child: Text('Aucune donnée de chaleur disponible',
                            style: TextStyle(fontSize: 12, color: AppColors.gris)))
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 1.6,
                            ),
                            itemCount: zones.length,
                            itemBuilder: (_, i) {
                              final z = zones[i];
                              final total = z['total'] as int? ?? 0;
                              final alerts = z['alerts'] as int? ?? 0;
                              final name = z['zone_name'] as String? ?? 'Zone ${i + 1}';
                              final intensity = maxVal > 0 ? total / maxVal : 0.0;
                              final color = intensity > 0.6
                                  ? AppColors.rouge
                                  : intensity > 0.3
                                      ? AppColors.orange
                                      : AppColors.vert;

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.08 + intensity * 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: color.withValues(alpha: 0.3 + intensity * 0.4)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(name,
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: color,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text('$total', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(Icons.warning, size: 12, color: AppColors.rouge.withValues(alpha: 0.6)),
                                        const SizedBox(width: 3),
                                        Text('$alerts alertes', style: const TextStyle(fontSize: 10, color: AppColors.gris)),
                                        const SizedBox(width: 10),
                                        Icon(Icons.visibility, size: 12, color: AppColors.orange.withValues(alpha: 0.6)),
                                        const SizedBox(width: 3),
                                        Text('${z['vigilance'] ?? 0} vigil.', style: const TextStyle(fontSize: 10, color: AppColors.gris)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: intensity,
                                        backgroundColor: const Color(0xFFDDDDDD),
                                        valueColor: AlwaysStoppedAnimation(color),
                                        minHeight: 4,
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
          NavBar(active: 'home', onTap: widget.onNavigate),
        ],
      ),
    );
  }

  Widget _dot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.gris)),
      ],
    );
  }
}