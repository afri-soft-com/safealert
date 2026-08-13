import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/incident_provider.dart';
import '../services/local_database.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';

/// File hors-ligne : en attente / échoué / renvoyer.
class OfflineQueueScreen extends StatefulWidget {
  final VoidCallback onBack;
  const OfflineQueueScreen({super.key, required this.onBack});

  @override
  State<OfflineQueueScreen> createState() => _OfflineQueueScreenState();
}

class _OfflineQueueScreenState extends State<OfflineQueueScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _flushing = false;
  String? _lastSyncMsg;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final rows = await LocalDatabase().listPending();
    if (!mounted) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'sos':
        return 'Alerte SOS';
      case 'report':
        return 'Signalement';
      case 'group_message':
        return 'Message de groupe';
      default:
        return kind;
    }
  }

  String _statusLabel(int attempts) {
    if (attempts >= 3) return 'Échoué';
    if (attempts > 0) return 'À renvoyer';
    return 'En attente';
  }

  Color _statusColor(int attempts) {
    if (attempts >= 3) return AppColors.rouge;
    if (attempts > 0) return AppColors.orange;
    return AppColors.bleuFonce;
  }

  Future<void> _retryAll() async {
    setState(() => _flushing = true);
    final sent = await context.read<IncidentProvider>().flushOfflineQueue();
    if (!mounted) return;
    setState(() {
      _flushing = false;
      _lastSyncMsg = sent > 0
          ? '$sent élément(s) synchronisé(s)'
          : 'Rien à synchroniser pour le moment';
    });
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(title: 'Envois en attente', onBackTap: widget.onBack),
          if (_lastSyncMsg != null)
            Container(
              width: double.infinity,
              color: AppColors.vert.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(_lastSyncMsg!, style: const TextStyle(fontSize: 12, color: AppColors.vert)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _items.isEmpty
                        ? 'Aucun envoi en attente. Tout est à jour.'
                        : '${_items.length} élément(s) non envoyé(s)',
                    style: const TextStyle(fontSize: 12, color: AppColors.gris),
                  ),
                ),
                TextButton.icon(
                  onPressed: _flushing ? null : _retryAll,
                  icon: _flushing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync, size: 16),
                  label: const Text('Renvoyer', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(
                        child: Text('✓ Synchronisé',
                            style: TextStyle(fontSize: 14, color: AppColors.vert, fontWeight: FontWeight.w600)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(14),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final item = _items[i];
                          final attempts = item['attempts'] as int? ?? 0;
                          final kind = item['kind'] as String? ?? '';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.grisClair),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.cloud_upload_outlined,
                                    color: _statusColor(attempts), size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_kindLabel(kind),
                                          style: const TextStyle(
                                              fontSize: 13, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${_statusLabel(attempts)}'
                                        '${attempts > 0 ? ' · $attempts essai(s)' : ''}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _statusColor(attempts),
                                        ),
                                      ),
                                    ],
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
    );
  }
}
