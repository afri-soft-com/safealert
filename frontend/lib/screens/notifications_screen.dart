import 'package:flutter/material.dart';
import '../services/fcm_service.dart';
import '../services/inbox_service.dart';
import '../theme.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';

class NotificationsScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const NotificationsScreen({super.key, this.onBack});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      InboxService().refresh();
    });
  }

  String _when(dynamic raw) {
    final dt = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inHours < 1) return 'Il y a ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'Il y a ${diff.inHours} h';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final id = item['id']?.toString();
    if (id != null && item['read_at'] == null) {
      await InboxService().markRead(id);
    }
    final payload = item['payload'];
    if (payload is! Map) return;
    final data = Map<String, dynamic>.from(payload);
    final type = data['type']?.toString() ?? '';
    const openable = {
      'sos_alert',
      'nearby_alert',
      'group_sos',
      'group_report',
      'sector_sos',
      'trust_zone_alert',
      'false_alarm',
      'group_false_alarm',
      'group_safe',
      'safety_ping_ask',
      'safety_ping_missed',
      'neighborhood_digest',
    };
    if (openable.contains(type)) {
      FCMService().queueOpenFromData(data);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: InboxService(),
        builder: (context, _) {
          final inbox = InboxService();
          return Column(
            children: [
              const StatusBar(),
              TopBar(title: 'Notifications', onBackTap: widget.onBack),
              if (inbox.unread > 0)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: inbox.markAllRead,
                    child: const Text('Tout marquer comme lu'),
                  ),
                ),
              Expanded(
                child: inbox.loading && inbox.items.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : inbox.items.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Aucune notification reçue pour le moment.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.gris, fontSize: 15),
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: inbox.refresh,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                              itemCount: inbox.items.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final item = inbox.items[i];
                                final unread = item['read_at'] == null;
                                return ListTile(
                                  onTap: () => _open(item),
                                  leading: Icon(
                                    unread
                                        ? Icons.notifications_active
                                        : Icons.notifications_none,
                                    color: unread ? AppColors.rouge : AppColors.gris,
                                  ),
                                  title: Text(
                                    (item['title']?.toString().isNotEmpty ?? false)
                                        ? item['title'].toString()
                                        : 'SafeAlert',
                                    style: TextStyle(
                                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${item['body'] ?? ''}\n${_when(item['created_at'])}',
                                    style: const TextStyle(fontSize: 12, height: 1.3),
                                  ),
                                  trailing: unread
                                      ? Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: AppColors.rouge,
                                            shape: BoxShape.circle,
                                          ),
                                        )
                                      : null,
                                );
                              },
                            ),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}
