import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/incident_provider.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';
import '../widgets/nav_bar.dart';

class DashboardScreen extends StatefulWidget {
  final ValueChanged<String> onNavigate;
  final VoidCallback? onBack;
  const DashboardScreen({super.key, required this.onNavigate, this.onBack});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<IncidentProvider>().fetchStats();
      context.read<IncidentProvider>().fetchIncidents();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ip = context.watch<IncidentProvider>();
    final stats = ip.stats;
    final incidents = ip.incidents;

    final totalIncidents = stats?['total_incidents'] as int? ?? incidents.length;
    final totalSos = stats?['total_sos'] as int? ?? 0;
    final activeUsers = stats?['active_users'] as int? ?? 0;
    final safeZones = stats?['safe_zones'] as int? ?? 0;

    final rawDays = stats?['incidents_by_day'] as List?;
    final barData = rawDays != null
        ? rawDays.map((d) => _BarData(
            d['day'] as String? ?? '?',
            (d['count'] as num?)?.toDouble() ?? 0,
            _colorForCount((d['count'] as num?)?.toDouble() ?? 0),
          )).toList()
        : _defaultBars;

    final maxVal = barData.map((b) => b.val).reduce((a, b) => a > b ? a : b);

    final rawHours = stats?['risk_hours'] as List?;
    final riskData = rawHours != null
        ? rawHours.map((h) => _RiskData(
            h['label'] as String? ?? '?',
            (h['level'] as num?)?.toInt() ?? 0,
            _colorForCount((h['level'] as num?)?.toDouble() ?? 0),
          )).toList()
        : _defaultRisk;

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(title: 'Tableau de bord — Votre quartier', onBackTap: widget.onBack),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: RefreshIndicator(
                onRefresh: () async {
                  await ip.fetchStats();
                  await ip.fetchIncidents();
                },
                child: ListView(
                  children: [
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.35,
                      children: [
                        _metricCard('⚠️', '$totalIncidents', 'Incidents cette semaine', AppColors.rouge),
                        _metricCard('🆘', '$totalSos', 'Alertes SOS envoyées', AppColors.orange),
                        _metricCard('👥', '$activeUsers', 'Utilisateurs actifs', AppColors.bleu),
                        _metricCard('🟢', '$safeZones', 'Zones sécurisées', AppColors.vert),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.grisClair,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('INCIDENTS PAR JOUR (7 derniers jours)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final chartH = constraints.maxWidth < 340 ? 96.0 : 80.0;
                              final barMax = chartH - 32;
                              return SizedBox(
                                height: chartH,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: barData.map((b) {
                                    final barH = maxVal > 0 ? (b.val / maxVal) * barMax : 0.0;
                                    return Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('${b.val.toInt()}', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: b.color)),
                                          const SizedBox(height: 2),
                                          Container(
                                            width: double.infinity,
                                            height: barH,
                                            decoration: BoxDecoration(
                                              color: b.color,
                                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(b.label, style: const TextStyle(fontSize: 7, color: AppColors.gris), overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.grisClair,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('HEURES À RISQUE',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
                          const SizedBox(height: 10),
                          ...riskData.map((h) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(h.label, style: const TextStyle(fontSize: 10, color: AppColors.gris), overflow: TextOverflow.ellipsis),
                                    ),
                                    Text('${h.level}%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: h.color)),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: h.level / 100,
                                    backgroundColor: const Color(0xFFDDDDDD),
                                    valueColor: AlwaysStoppedAnimation(h.color),
                                    minHeight: 6,
                                  ),
                                ),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          NavBar(active: 'dashboard', onTap: widget.onNavigate),
        ],
      ),
    );
  }

  Color _colorForCount(double val) {
    if (val >= 6) return AppColors.rouge;
    if (val >= 3) return AppColors.orange;
    return AppColors.vert;
  }

  Widget _metricCard(String icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.grisClair,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 8, color: AppColors.gris, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  static const _defaultBars = [
    _BarData('Lun', 2, AppColors.vert),
    _BarData('Mar', 5, AppColors.orange),
    _BarData('Mer', 3, AppColors.orange),
    _BarData('Jeu', 8, AppColors.rouge),
    _BarData('Ven', 6, AppColors.rouge),
    _BarData('Sam', 4, AppColors.orange),
    _BarData('Dim', 1, AppColors.vert),
  ];

  static const _defaultRisk = [
    _RiskData('18h – 20h', 90, AppColors.rouge),
    _RiskData('20h – 22h', 75, AppColors.rouge),
    _RiskData('12h – 14h', 45, AppColors.orange),
    _RiskData('06h – 08h', 20, AppColors.vert),
  ];
}

class _BarData {
  final String label;
  final double val;
  final Color color;
  const _BarData(this.label, this.val, this.color);
}

class _RiskData {
  final String label;
  final int level;
  final Color color;
  const _RiskData(this.label, this.level, this.color);
}