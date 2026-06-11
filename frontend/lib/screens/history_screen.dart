import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/history_provider.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';
import '../widgets/nav_bar.dart';

class HistoryScreen extends StatefulWidget {
  final void Function(String) onNavigate;
  final VoidCallback? onBack;
  const HistoryScreen({super.key, required this.onNavigate, this.onBack});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HistoryProvider>().fetchHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hp = context.watch<HistoryProvider>();
    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(title: 'Mon historique', onBackTap: widget.onBack),
          Expanded(
            child: hp.loading
                ? const Center(child: CircularProgressIndicator())
                : hp.history.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              hp.isOffline ? 'Données non disponibles hors-ligne' : 'Aucun incident',
                              style: const TextStyle(fontSize: 16, color: AppColors.gris),
                            ),
                            if (hp.isOffline) const SizedBox(height: 8),
                            if (hp.isOffline)
                              TextButton.icon(
                                onPressed: () => hp.fetchHistory(),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Réessayer'),
                              ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => hp.fetchHistory(),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: hp.history.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final item = hp.history[i];
                            return ListTile(
                              leading: Text(
                                hp.typeIcon(item['incident_type'] as String?),
                                style: const TextStyle(fontSize: 24),
                              ),
                              title: Text(
                                _typeLabel(item['incident_type'] as String?),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                '${_formatDate(item['created_at'] as String?)}  ·  ${hp.statusLabel(item['status'] as String?)}',
                                style: const TextStyle(fontSize: 13),
                              ),
                              trailing: item['status'] == 'active'
                                  ? TextButton(
                                      onPressed: () => hp.cancelSOS(item['id'] as int),
                                      child: const Text('Annuler', style: TextStyle(color: AppColors.rouge)),
                                    )
                                  : null,
                            );
                          },
                        ),
                      ),
          ),
          NavBar(active: 'home', onTap: widget.onNavigate),
        ],
      ),
    );
  }

  String _typeLabel(String? type) {
    switch (type) {
      case 'sos':
        return 'Alerte SOS';
      case 'sos_discret':
        return 'SOS Discret';
      case 'vol':
        return 'Vol';
      case 'agression':
        return 'Agression';
      case 'accident':
        return 'Accident';
      case 'incendie':
        return 'Incendie';
      case 'autre':
        return 'Autre';
      default:
        return 'Signalement';
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year} ${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
