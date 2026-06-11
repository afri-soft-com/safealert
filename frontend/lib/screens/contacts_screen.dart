import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/contacts_provider.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';
import '../widgets/nav_bar.dart';

class ContactsScreen extends StatefulWidget {
  final ValueChanged<String> onNavigate;
  const ContactsScreen({super.key, required this.onNavigate});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ContactsProvider>().fetchContacts();
    });
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ajouter un contact', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                hintText: 'Nom complet',
                hintStyle: const TextStyle(fontSize: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: 'Numéro de téléphone',
                hintStyle: const TextStyle(fontSize: 13),
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
              if (nameCtrl.text.trim().isEmpty || phoneCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              await context.read<ContactsProvider>().addContact(
                nameCtrl.text.trim(),
                phoneCtrl.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.bleuFonce,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Ajouter', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContactsProvider>();
    final contacts = provider.contacts;
    final onlineCount = contacts.where((c) => c['is_online'] == true).length;

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          const TopBar(title: 'Cercle de confiance'),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
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
                          : '✅ $onlineCount contacts en ligne — Alertés en cas de SOS',
                      style: TextStyle(fontSize: 11,
                          color: provider.isOffline ? const Color(0xFF7A4F00) : AppColors.vert,
                          fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: provider.loading
                        ? const Center(child: CircularProgressIndicator())
                        : contacts.isEmpty
                            ? const Center(child: Text('Aucun contact. Ajoutez votre premier contact de confiance.',
                                style: TextStyle(fontSize: 12, color: AppColors.gris)))
                            : ListView.separated(
                                itemCount: contacts.length,
                                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF0F0F0)),
                                itemBuilder: (_, i) {
                                  final c = contacts[i];
                                  final initials = _initials(c['contact_name'] as String? ?? '??');
                                  final colors = _avatarColors;
                                  final color = colors[i % colors.length];
                                  final isOnline = c['is_online'] == true;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: Row(
                                      children: [
                                        Stack(
                                          children: [
                                            Container(
                                              width: 42, height: 42,
                                              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                              child: Center(child: Text(initials,
                                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
                                            ),
                                            Positioned(
                                              right: 0, bottom: 0,
                                              child: Container(
                                                width: 11, height: 11,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: isOnline ? AppColors.vert : const Color(0xFFCCCCCC),
                                                  border: Border.all(color: Colors.white, width: 2),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(c['contact_name'] as String? ?? 'Contact',
                                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.bleuFonce)),
                                              Text(c['contact_phone'] as String? ?? '',
                                                  style: const TextStyle(fontSize: 10, color: AppColors.gris)),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(color: AppColors.grisClair, borderRadius: BorderRadius.circular(8)),
                                          child: const Text('📲', style: TextStyle(fontSize: 14)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _showAddDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.bleuFonce,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('+ Ajouter un contact de confiance',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          NavBar(active: 'contacts', onTap: widget.onNavigate),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.length == 1) return parts[0].substring(0, 2).toUpperCase();
    return '??';
  }

  static const _avatarColors = [
    Color(0xFF185FA5), Color(0xFF3B6D11), Color(0xFFE86A1A),
    Color(0xFF993556), Color(0xFF0D1B2A), Color(0xFFCC1C1C),
  ];
}