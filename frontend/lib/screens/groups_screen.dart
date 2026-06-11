import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/groups_provider.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';
import '../widgets/nav_bar.dart';

class GroupsScreen extends StatefulWidget {
  final ValueChanged<String> onNavigate;
  const GroupsScreen({super.key, required this.onNavigate});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<GroupsProvider>();
      p.fetchMyGroups();
      p.fetchDiscoverable();
    });
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final zoneCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Créer un groupe', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                hintText: 'Nom du groupe',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Description (optionnelle)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: zoneCtrl,
              decoration: InputDecoration(
                hintText: 'Zone / quartier (optionnel)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(fontSize: 13)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              await context.read<GroupsProvider>().createGroup(
                nameCtrl.text.trim(),
                description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                zoneName: zoneCtrl.text.trim().isEmpty ? null : zoneCtrl.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.bleuFonce,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Créer', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _showJoinDialog() {
    final codeCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rejoindre un groupe', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: codeCtrl,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: 'Code d\'invitation (ex: A1B2C3D4)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(fontSize: 13)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (codeCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              await context.read<GroupsProvider>().joinGroup(codeCtrl.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.vert,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Rejoindre', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<GroupsProvider>();
    final myGroups = p.myGroups;
    final discoverable = p.discoverable;

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          const TopBar(title: 'Groupes de voisins'),
          Expanded(
            child: p.loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _showCreateDialog,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Créer', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.bleuFonce,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _showJoinDialog,
                              icon: const Icon(Icons.group_add, size: 16),
                              label: const Text('Rejoindre', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.vert,
                                side: const BorderSide(color: AppColors.vert),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (myGroups.isNotEmpty) ...[
                        const Text('MES GROUPES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
                        const SizedBox(height: 8),
                        ...myGroups.map((g) => _groupCard(g, p)),
                        const SizedBox(height: 16),
                      ],
                      if (discoverable.isNotEmpty) ...[
                        const Text('GROUPES À DÉCOUVRIR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
                        const SizedBox(height: 8),
                        ...discoverable.map((g) => _discoverCard(g, p)),
                      ],
                      if (myGroups.isEmpty && discoverable.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text('Aucun groupe pour le moment.\nCréez ou rejoignez un groupe de voisins.',
                                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.gris)),
                          ),
                        ),
                    ],
                  ),
          ),
          NavBar(active: 'home', onTap: widget.onNavigate),
        ],
      ),
    );
  }

  Widget _groupCard(Map<String, dynamic> g, GroupsProvider p) {
    final id = g['id'] as String? ?? '';
    final name = g['name'] as String? ?? '';
    final zone = g['zone_name'] as String? ?? '';
    final members = g['member_count'] as int? ?? 0;
    final code = g['invite_code'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.blanc,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.bleuFonce,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(child: Text('👥', style: TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
                    Row(
                      children: [
                        Flexible(
                          child: Text('$members membres', style: const TextStyle(fontSize: 10, color: AppColors.gris), overflow: TextOverflow.ellipsis),
                        ),
                        if (zone.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text('📍 $zone', style: const TextStyle(fontSize: 10, color: AppColors.gris), overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.grisClair,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('📋 $code', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.bleuFonce), overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => p.leaveGroup(id),
              icon: const Icon(Icons.exit_to_app, size: 14),
              label: const Text('Quitter le groupe', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.rouge,
                side: const BorderSide(color: AppColors.rouge),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _discoverCard(Map<String, dynamic> g, GroupsProvider p) {
    final name = g['name'] as String? ?? '';
    final zone = g['zone_name'] as String? ?? '';
    final members = g['member_count'] as int? ?? 0;
    final creator = g['created_by_name'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.blanc,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.grisClair,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(child: Text('🏘', style: TextStyle(fontSize: 16))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.bleuFonce)),
                Text('$members membres · Par $creator${zone.isNotEmpty ? ' · $zone' : ''}',
                    style: const TextStyle(fontSize: 10, color: AppColors.gris)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}