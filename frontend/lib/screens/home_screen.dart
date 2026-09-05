import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/auth_provider.dart';
import '../providers/incident_provider.dart';
import '../services/app_config_service.dart';
import '../utils/location_format.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';
import '../widgets/nav_bar.dart';

class HomeScreen extends StatefulWidget {
  final ValueChanged<String> onNavigate;
  const HomeScreen({super.key, required this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _alertSent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<IncidentProvider>().fetchIncidents(hours: 24);
    });
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes} min';
      if (diff.inHours < 24) return '${diff.inHours}h';
      return '${diff.inDays}j';
    } catch (_) {
      return '';
    }
  }

  String _incidentLabel(IncidentProvider provider, Map<String, dynamic> inc) {
    final type = inc['incident_type'] as String? ?? 'incident';
    if (type == 'sos' || type == 'sos_discret') {
      return provider.labelForType(type);
    }
    final label = provider.labelForType(type);
    if (label == type || label == 'Signalement') return 'Incident signalé';
    return '$label signalé';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final incidentProvider = context.watch<IncidentProvider>();
    final pseudo = auth.user?['pseudo'] as String?;
    final greetingName = (pseudo != null && pseudo.trim().isNotEmpty)
        ? pseudo.trim()
        : auth.roleLabel;
    final incidents = incidentProvider.incidents;
    final loadingIncidents = incidentProvider.loading && incidents.isEmpty;
    final activeCount = incidents.length;
    final latest = incidents.isNotEmpty ? incidents.first : null;
    final recentActivities = incidents.take(5).toList();

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(sub: 'Bonjour, $greetingName', onMenuTap: () => widget.onNavigate('settings')),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
              children: [
                if (loadingIncidents)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.blanc,
                      border: Border.all(color: const Color(0xFFEEEEEE)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Chargement des alertes…',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.gris),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (latest != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.rougeLight,
                      border: Border.all(color: AppColors.rouge, width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Text('⚠️', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Alerte active — ${_incidentLabel(incidentProvider, latest)}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.rouge),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                LocationFormat.fromIncident(latest),
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.bleuFonce),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Signalé il y a ${_timeAgo(latest['created_at'] as String?)}',
                                style: const TextStyle(fontSize: 11, color: AppColors.gris),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.vertClair,
                      border: Border.all(color: AppColors.vert),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Text('✅', style: TextStyle(fontSize: 20)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text('Aucune alerte active dans les dernières 24h',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.vert)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() => _alertSent = true);
                      Future.delayed(const Duration(seconds: 3), () {
                        if (mounted) setState(() => _alertSent = false);
                      });
                      widget.onNavigate('sos');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _alertSent ? AppColors.rougeDark : AppColors.rouge,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      elevation: _alertSent ? 0 : 4,
                      shadowColor: AppColors.rouge.withValues(alpha: 0.3),
                    ),
                    child: Text(
                      _alertSent ? '✅ ALERTE ENVOYÉE !' : '🆘  BOUTON SOS',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.15,
                  children: [
                    _buildCard('🗺', 'Carte des zones', '$activeCount alerte${activeCount > 1 ? 's' : ''} (24h)', () => widget.onNavigate('map'), AppColors.bleu),
                    _buildCard('👥', 'Mes contacts', 'Cercle de confiance', () => widget.onNavigate('contacts'), AppColors.vert),
                    _buildCard('📞', 'Urgences', 'Appel en 1 tap', () => widget.onNavigate('annuaire'), AppColors.orange),
                    _buildCard('🛣️', 'Trajet sécurisé', 'ETA + alerte auto', () => widget.onNavigate('trip'), AppColors.vert),
                    _buildCard('📊', 'Statistiques', 'Votre quartier', () => widget.onNavigate('dashboard'), AppColors.gris),
                    _buildCard('🏘', 'Groupes voisins', 'Voisins & entraide', () => widget.onNavigate('groups'), AppColors.bleuFonce),
                    _buildCard('🏠', 'Zones confiance', 'Domicile / travail', () => widget.onNavigate('trust_zones'), AppColors.bleuFonce),
                    _buildCard('🏘️', 'Veille quartier', 'Résumé quotidien', () => widget.onNavigate('neighborhood'), AppColors.orange),
                    _buildCard('🛡', 'Conseils sécurité', 'Astuces hors-ligne', () => widget.onNavigate('safety'), AppColors.rouge),
                    if (AppConfigService().heatmapEnabled)
                      _buildCard('🔥', 'Carte chaleur', 'Densité incidents', () => widget.onNavigate('heatmap'), AppColors.orange),
                    _buildCard('📋', 'Mon historique', 'Mes alertes', () => widget.onNavigate('history'), AppColors.gris),
                    _buildCard('📖', 'Aide / Manuel', 'Guide d\'utilisation', () => widget.onNavigate('help'), AppColors.bleu),
                  ],
                ),
                const SizedBox(height: 14),
                if (incidents.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.blanc,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEEEEEE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ACTIVITÉ RÉCENTE (24h)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.rouge, letterSpacing: 1)),
                        const SizedBox(height: 8),
                        ...recentActivities.asMap().entries.map((entry) {
                          final inc = entry.value;
                          final isLast = entry.key == recentActivities.length - 1;
                          final type = inc['incident_type'] as String? ?? 'incident';
                          final icon = type == 'agression' || type == 'sos' ? '🔴' : (type == 'vol' || type == 'suspect' ? '🟡' : '🟢');
                          final desc = (inc['description'] as String?)?.trim();
                          final title = (desc != null && desc.isNotEmpty)
                              ? '${_incidentLabel(incidentProvider, inc)} — $desc'
                              : _incidentLabel(incidentProvider, inc);
                          return _activityItem(
                            icon,
                            title,
                            LocationFormat.fromIncident(inc),
                            _timeAgo(inc['created_at'] as String?),
                            isLast,
                          );
                        }),
                      ],
                    ),
                  ),
                if (auth.canAccessOps)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _buildCard('👑', 'Mode responsable', 'Gérer les incidents du secteur',
                        () => widget.onNavigate('leader'), AppColors.bleuFonce),
                  ),
                if (auth.canAccessAdmin)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _buildCard('⚙️', 'Administration', 'Utilisateurs, abonnements et rôles',
                        () => widget.onNavigate('admin'), AppColors.gris),
                  ),
              ],
            ),
          ),
          NavBar(active: 'home', onTap: widget.onNavigate),
        ],
      ),
    );
  }

  Widget _buildCard(String icon, String label, String sub, VoidCallback onTap, Color accent) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.blanc,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.bleuFonce), maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(sub, style: const TextStyle(fontSize: 9, color: AppColors.gris), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _activityItem(
    String icon,
    String title,
    String placeLine,
    String time,
    bool isLast,
  ) {
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: AppColors.bleuFonce, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (placeLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Lieu : $placeLine',
                    style: const TextStyle(fontSize: 11, color: AppColors.bleuFonce, fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (time.isNotEmpty)
                  Text('Il y a $time', style: const TextStyle(fontSize: 10, color: AppColors.gris)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
