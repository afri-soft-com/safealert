import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../theme.dart';
import '../services/api_service.dart';
import '../providers/leader_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/location_format.dart';
import '../widgets/app_feedback.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';
import '../widgets/nav_bar.dart';

class LeaderScreen extends StatefulWidget {
  final ValueChanged<String> onNavigate;
  final VoidCallback? onBack;
  const LeaderScreen({super.key, required this.onNavigate, this.onBack});

  @override
  State<LeaderScreen> createState() => _LeaderScreenState();
}

class _LeaderScreenState extends State<LeaderScreen> {
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<LeaderProvider>();
      p.fetchSectorIncidents();
      p.fetchSectorStats();
    });
  }

  Future<void> _downloadReport() async {
    setState(() => _downloading = true);
    try {
      final api = ApiService();
      final token = api.token;
      if (token == null) return;

      final url = '${ApiService.baseUrl}/report?days=7';
      final res = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) throw Exception('Erreur serveur');

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rapport-incidents-${DateTime.now().toIso8601String().split('T')[0]}.pdf');
      await file.writeAsBytes(res.bodyBytes);

      if (mounted) {
        showAppSnackBar(
          context,
          'Rapport PDF enregistré dans vos documents.',
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          e,
          isError: true,
          fallback: 'Impossible de télécharger le rapport.',
        );
      }
    }
    if (mounted) setState(() => _downloading = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.canAccessOps) {
      return AccessDeniedView(
        title: 'Accès réservé',
        message: 'Le mode responsable est réservé aux responsables, agents et administrateurs.',
        onBack: widget.onBack,
      );
    }

    final p = context.watch<LeaderProvider>();
    final stats = p.stats;
    final incidents = p.incidents;
    final sectorName = auth.user?['sector_name'] as String? ?? stats?['sector_name'] as String?;

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(title: 'Secteur — Vue responsable', onBackTap: widget.onBack),
          if (sectorName != null && sectorName.isNotEmpty)
            Container(
              width: double.infinity,
              color: AppColors.grisClair,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Text('Filtre secteur : $sectorName',
                  style: const TextStyle(fontSize: 10, color: AppColors.gris, fontWeight: FontWeight.w600)),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await p.fetchSectorIncidents();
                await p.fetchSectorStats();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                children: [
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 0.9,
                    children: [
                      _miniStat('🟠', '${stats?['active'] ?? 0}', 'Actifs', AppColors.rouge),
                      _miniStat('✅', '${stats?['verified'] ?? 0}', 'Vérifiés', AppColors.vert),
                      _miniStat('🔵', '${stats?['resolved'] ?? 0}', 'Résolus', AppColors.bleu),
                      _miniStat('⏰', '${stats?['last_24h'] ?? 0}', '24h', AppColors.orange),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _downloading ? null : _downloadReport,
                      icon: _downloading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.description, size: 16),
                      label: Text(_downloading ? 'Génération...' : '📄  Générer le rapport PDF (7 jours)',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.bleuFonce,
                        side: const BorderSide(color: AppColors.bleuFonce),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final api = ApiService();
                          final token = api.token;
                          if (token == null) return;
                          final url = '${ApiService.baseUrl}/ops/reports/sector?format=csv&days=7';
                          final res = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
                          if (res.statusCode != 200) throw Exception('Erreur');
                          final dir = await getApplicationDocumentsDirectory();
                          final file = File('${dir.path}/secteur-7j.csv');
                          await file.writeAsBytes(res.bodyBytes);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('CSV : ${file.path}', style: const TextStyle(fontSize: 11))),
                            );
                          }
                        } catch (_) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Export CSV impossible'), backgroundColor: AppColors.rouge),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.table_chart, size: 16),
                      label: const Text('📊  Export CSV secteur (7 jours)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.vert,
                        side: const BorderSide(color: AppColors.vert),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('INCIDENTS RÉCENTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
                  const SizedBox(height: 8),
                  if (p.loading)
                    const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                  else if (incidents.isEmpty)
                    const Center(child: Padding(padding: EdgeInsets.all(20),
                        child: Text('Aucun incident actif dans le secteur', style: TextStyle(fontSize: 12, color: AppColors.gris))))
                  else
                    ...incidents.map((inc) => _buildIncidentCard(inc, p)),
                ],
              ),
            ),
          ),
          NavBar(active: 'home', onTap: widget.onNavigate),
        ],
      ),
    );
  }

  Widget _miniStat(String icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.blanc,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 8, color: AppColors.gris)),
        ],
      ),
    );
  }

  Widget _buildIncidentCard(Map<String, dynamic> inc, LeaderProvider p) {
    final id = inc['id'] as String? ?? '';
    final type = inc['incident_type'] as String? ?? 'Incident';
    final desc = inc['description'] as String? ?? '';
    final reporter = inc['reporter'] as String? ?? 'Anonyme';
    final locationLine = LocationFormat.fromIncident(inc);
    final verif = inc['verified_by'] as int? ?? 0;
    final status = inc['status'] as String? ?? 'active';
    final color = _statusColor(status);

    String statusLabel;
    switch (status) {
      case 'verified':
        statusLabel = '✓ VÉRIFIÉ';
        break;
      case 'acknowledged':
        statusLabel = '👋 PRISE EN CHARGE';
        break;
      case 'in_progress':
        statusLabel = '🔧 EN COURS';
        break;
      default:
        statusLabel = '';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.blanc,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(type.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color), overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 6),
              if (statusLabel.isNotEmpty)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(statusLabel, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color), overflow: TextOverflow.ellipsis),
                  ),
                ),
              const SizedBox(width: 6),
              Text('✅ $verif', style: const TextStyle(fontSize: 10, color: AppColors.gris)),
            ],
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(desc, style: const TextStyle(fontSize: 12, color: AppColors.bleuFonce)),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Flexible(
                child: Text('Par $reporter', style: const TextStyle(fontSize: 10, color: AppColors.gris), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '📍 $locationLine',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.bleuFonce),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          if (status == 'active' || status == 'verified' || status == 'acknowledged')
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => p.acknowledgeIncident(id),
                icon: const Icon(Icons.handshake, size: 16),
                label: Text(
                  status == 'acknowledged' ? 'Marquer en cours de traitement' : 'Prendre en charge',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.orange,
                  side: const BorderSide(color: AppColors.orange),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          if (status == 'active' || status == 'verified' || status == 'acknowledged' || status == 'in_progress')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final etaCtrl = TextEditingController(text: '15');
                    final eta = await showDialog<int>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('M\'assigner / en route', style: TextStyle(fontSize: 15)),
                        content: TextField(
                          controller: etaCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Temps estimé (minutes)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, int.tryParse(etaCtrl.text) ?? 15),
                            child: const Text('Confirmer'),
                          ),
                        ],
                      ),
                    );
                    if (eta == null || !mounted) return;
                    final auth = context.read<AuthProvider>();
                    final agentId = auth.user?['id']?.toString();
                    if (agentId == null) return;
                    await p.assignAgent(id, agentId, etaMinutes: eta);
                    await p.markEnRoute(id, etaMinutes: eta);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Citoyen informé : vous êtes en route')),
                      );
                    }
                  },
                  icon: const Icon(Icons.directions_run, size: 16),
                  label: const Text('Je pars (ETA visible citoyen)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.vert,
                    side: const BorderSide(color: AppColors.vert),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ),
          if (status == 'active' || status == 'verified' || status == 'acknowledged' || status == 'in_progress')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ctrl = TextEditingController();
                    final reason = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clôturer avec motif', style: TextStyle(fontSize: 15)),
                        content: TextField(
                          controller: ctrl,
                          decoration: const InputDecoration(
                            labelText: 'Motif',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                            child: const Text('Clôturer'),
                          ),
                        ],
                      ),
                    );
                    if (reason != null && reason.length >= 3) {
                      await p.closeWithReason(id, reason);
                    }
                  },
                  icon: const Icon(Icons.check_circle, size: 16),
                  label: const Text('Clôturer (motif requis)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.bleuFonce,
                    side: const BorderSide(color: AppColors.bleuFonce),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextButton(
              onPressed: () async {
                final ctrl = TextEditingController();
                final msgs = await p.fetchChat(id);
                if (!mounted) return;
                await showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Chat incident', style: TextStyle(fontSize: 15)),
                    content: SizedBox(
                      width: double.maxFinite,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 160,
                            child: ListView(
                              children: msgs
                                  .map((m) => Text('${m['pseudo']}: ${m['body']}',
                                      style: const TextStyle(fontSize: 12)))
                                  .toList(),
                            ),
                          ),
                          TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Message')),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
                      ElevatedButton(
                        onPressed: () async {
                          if (ctrl.text.trim().isEmpty) return;
                          await p.postChat(id, ctrl.text.trim());
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: const Text('Envoyer'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('💬 Chat ops', style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'verified':
      case 'resolved':
        return AppColors.vert;
      case 'in_progress':
        return AppColors.bleu;
      case 'acknowledged':
        return AppColors.orange;
      default:
        return AppColors.rouge;
    }
  }
}