import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/groups_provider.dart';
import '../services/location_service.dart';
import '../utils/location_format.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';

class GroupDetailScreen extends StatefulWidget {
  final Map<String, dynamic> group;
  const GroupDetailScreen({super.key, required this.group});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _pollTimer;
  final _messageCtrl = TextEditingController();

  String get _groupId => widget.group['id'] as String;
  String get _groupName => widget.group['name'] as String? ?? 'Groupe';
  bool get _isAdmin => (widget.group['my_role'] as String? ?? 'member') == 'admin';
  int get _pending => widget.group['pending_requests'] as int? ?? 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
        _pollActiveTab();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollActiveTab());
  }

  Future<void> _loadAll() async {
    final p = context.read<GroupsProvider>();
    await Future.wait([
      p.fetchMembers(_groupId),
      p.fetchMessages(_groupId),
      p.fetchAlerts(_groupId),
      if (_isAdmin && _pending > 0) p.fetchJoinRequests(_groupId),
    ]);
  }

  Future<void> _pollActiveTab() async {
    if (!mounted) return;
    final p = context.read<GroupsProvider>();
    switch (_tabController.index) {
      case 0:
        await p.fetchMembers(_groupId);
      case 1:
        await p.fetchMessages(_groupId);
      case 2:
        await p.fetchAlerts(_groupId);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;
    final p = context.read<GroupsProvider>();
    final ok = await p.sendMessage(_groupId, text);
    if (!mounted) return;
    if (ok) {
      _messageCtrl.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Impossible d\'envoyer le message', style: TextStyle(fontSize: 12)),
        backgroundColor: AppColors.rouge,
      ));
    }
  }

  void _showCreateAlertDialog() {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String alertType = 'info';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Nouvelle alerte locale', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: alertType,
                  decoration: InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'info', child: Text('ℹ️ Information', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'help_needed', child: Text('🆘 Aide demandée', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'offer_help', child: Text('🤝 Proposer de l\'aide', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'danger', child: Text('⚠️ Danger', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'power_outage', child: Text('⚡ Coupure d\'électricité', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'water_outage', child: Text('💧 Coupure d\'eau', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'flood', child: Text('🌊 Inondation', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'blocked_street', child: Text('🚧 Rue bloquée', style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (v) => setDialogState(() => alertType = v ?? 'info'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    hintText: 'Titre',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bodyCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Détails (optionnel)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler', style: TextStyle(fontSize: 13))),
            ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                final p = context.read<GroupsProvider>();
                final pos = await LocationService().getCurrentPosition();
                final ok = await p.createAlert(
                  _groupId,
                  type: alertType,
                  title: titleCtrl.text.trim(),
                  body: bodyCtrl.text.trim().isEmpty ? null : bodyCtrl.text.trim(),
                  lat: pos?.latitude,
                  lng: pos?.longitude,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok ? 'Alerte publiée' : 'Erreur lors de la publication',
                      style: const TextStyle(fontSize: 12)),
                  backgroundColor: ok ? AppColors.vert : AppColors.rouge,
                ));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Publier', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<GroupsProvider>();
    final members = p.membersFor(_groupId);
    final messages = p.messagesFor(_groupId);
    final alerts = p.alertsFor(_groupId);

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(title: _groupName, onBackTap: () => Navigator.pop(context)),
          TabBar(
            controller: _tabController,
            labelColor: AppColors.bleuFonce,
            unselectedLabelColor: AppColors.gris,
            indicatorColor: AppColors.bleuFonce,
            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            tabs: const [
              Tab(text: 'Membres'),
              Tab(text: 'Messages'),
              Tab(text: 'Alertes'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _membersTab(members, p),
                _messagesTab(messages),
                _alertsTab(alerts),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 2
          ? FloatingActionButton.extended(
              onPressed: _showCreateAlertDialog,
              backgroundColor: AppColors.orange,
              icon: const Icon(Icons.campaign, size: 18),
              label: const Text('Alerte', style: TextStyle(fontSize: 12)),
            )
          : null,
    );
  }

  Widget _membersTab(List<Map<String, dynamic>> members, GroupsProvider p) {
    final requests = p.joinRequestsFor(_groupId);
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (_isAdmin && requests.isNotEmpty) ...[
          const Text('DEMANDES EN ATTENTE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.orange)),
          const SizedBox(height: 8),
          ...requests.map((r) => _requestTile(r, p)),
          const SizedBox(height: 16),
        ],
        const Text('MEMBRES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
        const SizedBox(height: 8),
        if (members.isEmpty)
          const Center(child: Padding(
            padding: EdgeInsets.all(20),
            child: Text('Aucun membre', style: TextStyle(fontSize: 12, color: AppColors.gris)),
          ))
        else
          ...members.map(_memberTile),
      ],
    );
  }

  Widget _memberTile(Map<String, dynamic> m) {
    final pseudo = m['pseudo'] as String? ?? 'Citoyen';
    final phone = m['phone'] as String? ?? '';
    final role = m['role'] as String? ?? 'member';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.blanc,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.grisClair,
            child: Text(pseudo.isNotEmpty ? pseudo[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pseudo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                if (phone.isNotEmpty)
                  Text(phone, style: const TextStyle(fontSize: 10, color: AppColors.gris)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: role == 'admin' ? AppColors.bleuFonce.withValues(alpha: 0.1) : AppColors.grisClair,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(role == 'admin' ? 'Admin' : 'Membre',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                    color: role == 'admin' ? AppColors.bleuFonce : AppColors.gris)),
          ),
        ],
      ),
    );
  }

  Widget _requestTile(Map<String, dynamic> r, GroupsProvider p) {
    final id = r['id'] as String;
    final pseudo = r['pseudo'] as String? ?? 'Citoyen';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(pseudo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          TextButton(
            onPressed: () => p.rejectJoinRequest(id, _groupId),
            child: const Text('Refuser', style: TextStyle(fontSize: 11, color: AppColors.rouge)),
          ),
          ElevatedButton(
            onPressed: () => p.approveJoinRequest(id, _groupId),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.vert,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            child: const Text('Approuver', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _messagesTab(List<Map<String, dynamic>> messages) {
    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? const Center(child: Text('Aucun message.\nÉcrivez le premier !',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.gris)))
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: messages.length,
                  itemBuilder: (_, i) => _messageBubble(messages[i]),
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: const BoxDecoration(
            color: AppColors.blanc,
            border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageCtrl,
                  decoration: InputDecoration(
                    hintText: 'Votre message...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _sendMessage,
                icon: const Icon(Icons.send, color: AppColors.bleuFonce),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _messageBubble(Map<String, dynamic> m) {
    final author = m['author_pseudo'] as String? ?? 'Membre';
    final content = m['content'] as String? ?? '';
    final createdAt = m['created_at'] as String? ?? '';
    final time = createdAt.length >= 16 ? createdAt.substring(11, 16) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.grisClair,
            child: Text(author.isNotEmpty ? author[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.grisClair,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(author, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
                      const Spacer(),
                      if (time.isNotEmpty)
                        Text(time, style: const TextStyle(fontSize: 9, color: AppColors.gris)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(content, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertsTab(List<Map<String, dynamic>> alerts) {
    if (alerts.isEmpty) {
      return const Center(child: Text('Aucune alerte locale.\nPubliez une alerte d\'entraide.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.gris)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: alerts.length,
      itemBuilder: (_, i) => _alertCard(alerts[i]),
    );
  }

  Widget _alertCard(Map<String, dynamic> a) {
    final type = a['type'] as String? ?? 'info';
    final title = a['title'] as String? ?? '';
    final body = a['body'] as String? ?? '';
    final author = a['author_pseudo'] as String? ?? 'Membre';
    final createdAt = a['created_at'] as String? ?? '';

    final typeMeta = _alertTypeMeta(type);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: typeMeta.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: typeMeta.color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(typeMeta.emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
              ),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(body, style: const TextStyle(fontSize: 11, color: AppColors.gris)),
          ],
          if (a['lat'] != null && a['lng'] != null) ...[
            const SizedBox(height: 6),
            Text(
              '📍 ${LocationFormat.displayLine(lat: a['lat'] as num?, lng: a['lng'] as num?)}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.bleuFonce),
            ),
          ],
          const SizedBox(height: 6),
          Text('Par $author${createdAt.isNotEmpty ? ' · ${_formatDate(createdAt)}' : ''}',
              style: const TextStyle(fontSize: 9, color: AppColors.gris)),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    if (iso.length >= 16) return iso.substring(0, 16).replaceFirst('T', ' ');
    return iso;
  }

  ({String emoji, Color color}) _alertTypeMeta(String type) {
    switch (type) {
      case 'help_needed':
        return (emoji: '🆘', color: AppColors.rouge);
      case 'offer_help':
        return (emoji: '🤝', color: AppColors.vert);
      case 'danger':
        return (emoji: '⚠️', color: AppColors.rouge);
      case 'power_outage':
        return (emoji: '⚡', color: AppColors.orange);
      case 'water_outage':
        return (emoji: '💧', color: AppColors.bleuFonce);
      case 'flood':
        return (emoji: '🌊', color: AppColors.bleu);
      case 'blocked_street':
        return (emoji: '🚧', color: AppColors.orange);
      default:
        return (emoji: 'ℹ️', color: AppColors.bleuFonce);
    }
  }
}
