import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/admin_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_feedback.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';
import '../widgets/nav_bar.dart';

class AdminScreen extends StatefulWidget {
  final ValueChanged<String> onNavigate;
  final VoidCallback? onBack;
  const AdminScreen({super.key, required this.onNavigate, this.onBack});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _partnerNameCtrl = TextEditingController();
  final _grantQueryCtrl = TextEditingController();
  final Map<String, TextEditingController> _sectorCtrls = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<AdminProvider>();
      p.fetchUsers();
      p.fetchPartners();
      p.fetchSubscriptions();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _partnerNameCtrl.dispose();
    _grantQueryCtrl.dispose();
    for (final c in _sectorCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _sectorController(String userId, String initial) {
    return _sectorCtrls.putIfAbsent(userId, () => TextEditingController(text: initial));
  }

  Future<void> _showNewPartnerDialog() async {
    _partnerNameCtrl.clear();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau partenaire API', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: _partnerNameCtrl,
          decoration: const InputDecoration(hintText: 'Nom de l\'organisation', labelText: 'Partenaire'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, _partnerNameCtrl.text.trim()),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    final admin = context.read<AdminProvider>();
    final apiKey = await admin.createPartner(name);
    if (!mounted) return;
    if (apiKey != null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Clé API créée'),
          content: SelectableText('Conservez cette clé :\n\n$apiKey', style: const TextStyle(fontSize: 11)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } else {
      showAppSnackBar(
        context,
        admin.error ?? 'Impossible de créer le partenaire.',
        isError: true,
        fallback: 'Impossible de créer le partenaire.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.canAccessAdmin) {
      return AccessDeniedView(
        title: 'Accès réservé',
        message: 'Cette zone est réservée aux administrateurs.',
        onBack: widget.onBack,
      );
    }

    final p = context.watch<AdminProvider>();

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(title: 'Administration', onBackTap: widget.onBack),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.bleuFonce,
            unselectedLabelColor: AppColors.gris,
            indicatorColor: AppColors.bleuFonce,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 12),
            labelPadding: const EdgeInsets.symmetric(horizontal: 8),
            tabs: const [
              Tab(text: 'Utilisateurs'),
              Tab(text: 'Abonnements'),
              Tab(text: 'Partenaires'),
            ],
          ),
          if (p.error != null)
            Container(
              width: double.infinity,
              color: AppColors.rougeLight,
              padding: const EdgeInsets.all(8),
              child: Text(p.error!, style: const TextStyle(fontSize: 11, color: AppColors.rouge), maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildUsersTab(p, auth),
                _buildSubscriptionsTab(p),
                _buildPartnersTab(p, auth.isPlatformAdmin),
              ],
            ),
          ),
          NavBar(active: 'home', onTap: widget.onNavigate),
        ],
      ),
    );
  }

  Widget _buildUsersTab(AdminProvider p, AuthProvider auth) {
    if (p.loadingUsers) {
      return const Center(child: CircularProgressIndicator());
    }
    if (p.users.isEmpty) {
      return const Center(child: Text('Aucun utilisateur', style: TextStyle(fontSize: 12, color: AppColors.gris)));
    }
    return RefreshIndicator(
      onRefresh: () => p.fetchUsers(page: p.usersPage),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: p.users.length,
        itemBuilder: (ctx, i) => _userTile(p, auth, p.users[i]),
      ),
    );
  }

  Widget _userTile(AdminProvider p, AuthProvider auth, Map<String, dynamic> user) {
    final id = user['id'] as String;
    final role = user['role'] as String? ?? 'citizen';
    final sector = user['sector_name'] as String? ?? '';
    final sectorCtrl = _sectorController(id, sector);
    final isActive = user['is_active'] != false;
    final roleChoices = auth.isPlatformAdmin
        ? AdminProvider.roleLabels
        : {
            UserRoles.citizen: UserRoles.labels[UserRoles.citizen]!,
            UserRoles.leader: UserRoles.labels[UserRoles.leader]!,
            UserRoles.agent: UserRoles.labels[UserRoles.agent]!,
            if (AdminProvider.roleLabels.containsKey(role)) role: AdminProvider.roleLabels[role]!,
          };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.blanc,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user['pseudo'] as String? ?? '—',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.bleuFonce),
              overflow: TextOverflow.ellipsis),
          Text(user['phone'] as String? ?? '', style: const TextStyle(fontSize: 10, color: AppColors.gris), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Rôle : ', style: TextStyle(fontSize: 11, color: AppColors.gris)),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    isDense: true,
                    value: roleChoices.containsKey(role) ? role : 'citizen',
                    items: roleChoices.entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(
                                e.value,
                                style: const TextStyle(fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    selectedItemBuilder: (ctx) => roleChoices.entries
                        .map((e) => Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                e.value,
                                style: const TextStyle(fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null && v != role) {
                        showDialog<bool>(
                          context: context,
                          builder: (dlg) => AlertDialog(
                            title: const Text('Changer le rôle ?',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            content: Text(
                              'Nouveau rôle : ${AdminProvider.roleLabels[v] ?? v}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dlg, false), child: const Text('Annuler')),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(dlg, true),
                                child: const Text('Confirmer'),
                              ),
                            ],
                          ),
                        ).then((ok) {
                          if (ok == true) p.updateUserRole(id, v);
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: sectorCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Secteur géographique',
                    hintText: 'Ex. Gombe, Limete…',
                    labelStyle: const TextStyle(fontSize: 10),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.save, size: 18, color: AppColors.bleuFonce),
                onPressed: () {
                  final v = sectorCtrl.text.trim();
                  p.updateUserSector(id, v.isEmpty ? null : v);
                },
                tooltip: 'Enregistrer secteur',
              ),
            ],
          ),
          if (auth.isPlatformAdmin) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (dlg) => AlertDialog(
                      title: Text(isActive ? 'Désactiver ce compte ?' : 'Réactiver ce compte ?',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      content: Text(
                        isActive
                            ? 'La personne ne pourra plus se connecter.'
                            : 'Le compte pourra à nouveau se connecter.',
                        style: const TextStyle(fontSize: 12),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dlg, false), child: const Text('Annuler')),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(dlg, true),
                          child: Text(isActive ? 'Désactiver' : 'Activer'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true && mounted) {
                    await p.setUserActive(id, !isActive);
                  }
                },
                child: Text(
                  isActive ? 'Désactiver le compte' : 'Activer le compte',
                  style: TextStyle(fontSize: 11, color: isActive ? AppColors.rouge : AppColors.vert),
                ),
              ),
            ),
          ] else if (!isActive)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Compte inactif', style: TextStyle(fontSize: 11, color: AppColors.rouge)),
            ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionsTab(AdminProvider p) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _grantQueryCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Téléphone ou pseudo',
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  final q = _grantQueryCtrl.text.trim();
                  if (q.isEmpty) return;
                  final ok = await p.grantPremiumByQuery(q);
                  if (!mounted) return;
                  if (ok) {
                    _grantQueryCtrl.clear();
                    showAppSnackBar(context, 'Abonnement accordé (30 jours).');
                  } else {
                    showAppSnackBar(
                      context,
                      p.error ?? "Impossible d'accorder l'abonnement.",
                      isError: true,
                      fallback: "Impossible d'accorder l'abonnement.",
                    );
                  }
                },
                child: const Text('Accorder 30 j', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
        Expanded(
          child: p.loadingSubs
              ? const Center(child: CircularProgressIndicator())
              : p.subscriptions.isEmpty
                  ? const Center(
                      child: Text('Aucun abonnement', style: TextStyle(fontSize: 12, color: AppColors.gris)))
                  : RefreshIndicator(
                      onRefresh: () => p.fetchSubscriptions(page: p.subsPage),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: p.subscriptions.length,
                        itemBuilder: (ctx, i) {
                          final row = p.subscriptions[i];
                          final until = row['premium_until'] as String?;
                          DateTime? d;
                          if (until != null) d = DateTime.tryParse(until);
                          final active = d != null && d.isAfter(DateTime.now());
                          final id = row['id'] as String? ?? '';
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
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(row['pseudo'] as String? ?? '—',
                                          style: const TextStyle(
                                              fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
                                      Text(row['phone'] as String? ?? '',
                                          style: const TextStyle(fontSize: 10, color: AppColors.gris)),
                                      Text(
                                        d == null
                                            ? '—'
                                            : (active
                                                ? 'Actif jusqu\'au ${d.day}/${d.month}/${d.year}'
                                                : 'Expiré le ${d.day}/${d.month}/${d.year}'),
                                        style: TextStyle(
                                            fontSize: 11, color: active ? AppColors.vert : AppColors.gris),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => p.grantPremium(id),
                                  child: const Text('Prolonger', style: TextStyle(fontSize: 11)),
                                ),
                                TextButton(
                                  onPressed: () => p.revokePremium(id),
                                  child: const Text('Révoquer',
                                      style: TextStyle(fontSize: 11, color: AppColors.rouge)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildPartnersTab(AdminProvider p, bool canManagePartners) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.grisClair,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Les partenaires (ONG, autorités) ne sont pas des utilisateurs mobiles. '
              'Ils accèdent à SafeAlert via une clé API fournie ici — conservez-la hors de l\'application.',
              style: TextStyle(fontSize: 10, color: AppColors.gris, height: 1.4),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: canManagePartners ? _showNewPartnerDialog : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text(
                'Créer une clé partenaire',
                style: TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.bleuFonce,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
        Expanded(
          child: p.loadingPartners
              ? const Center(child: CircularProgressIndicator())
              : p.partners.isEmpty
                  ? const Center(child: Text('Aucun partenaire', style: TextStyle(fontSize: 12, color: AppColors.gris)))
                  : RefreshIndicator(
                      onRefresh: p.fetchPartners,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: p.partners.length,
                        itemBuilder: (ctx, i) {
                          final partner = p.partners[i];
                          final active = partner['is_active'] as bool? ?? true;
                          final key = partner['api_key'] as String? ?? '';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.blanc,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFEEEEEE)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(partner['partner_name'] as String? ?? '—',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: active ? AppColors.bleuFonce : AppColors.gris),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis),
                                        const SizedBox(height: 2),
                                        Text(
                                          active && key.length >= 8 ? 'Clé : ${key.substring(0, 8)}…' : (active ? 'Clé active' : 'Révoquée'),
                                          style: const TextStyle(fontSize: 10, color: AppColors.gris),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  if (active && canManagePartners)
                                    TextButton(
                                      onPressed: () async {
                                        final name = partner['partner_name'] as String? ?? 'ce partenaire';
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (dlg) => AlertDialog(
                                            title: const Text('Révoquer la clé ?',
                                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                            content: Text(
                                              'L\'accès de « $name » sera coupé immédiatement.',
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(dlg, false), child: const Text('Annuler')),
                                              ElevatedButton(
                                                onPressed: () => Navigator.pop(dlg, true),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppColors.rouge,
                                                  foregroundColor: Colors.white,
                                                ),
                                                child: const Text('Révoquer'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok == true && mounted) {
                                          await p.revokePartner(partner['id'] as String);
                                        }
                                      },
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text('Révoquer', style: TextStyle(fontSize: 10, color: AppColors.rouge)),
                                    )
                                  else
                                    const Text('Inactif', style: TextStyle(fontSize: 10, color: AppColors.gris)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
