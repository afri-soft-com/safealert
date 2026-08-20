import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../l10n/app_localizations.dart';
import '../widgets/status_bar.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/contacts_provider.dart';
import '../services/api_service.dart';
import '../services/contact_backup_service.dart';
import '../services/duress_pin_service.dart';
import '../widgets/app_feedback.dart';
import 'calculator_screen.dart' show kDiscreetUnlockCode;

class SettingsScreen extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onLogout;
  final VoidCallback? onPrivacy;
  final VoidCallback? onHelp;
  final VoidCallback? onLeader;
  final VoidCallback? onAdmin;
  final ValueChanged<String>? onNavigate;
  const SettingsScreen({
    super.key,
    required this.onBack,
    required this.onLogout,
    this.onPrivacy,
    this.onHelp,
    this.onLeader,
    this.onAdmin,
    this.onNavigate,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _discreetMode = false;
  bool _sharePresence = true;
  bool _sosNotifyGroups = true;
  bool _deleting = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPrefs());
  }

  Future<void> _loadPrefs() async {
    final auth = context.read<AuthProvider>();
    final prefs = await SharedPreferences.getInstance();
    // Mirror lock logic: local OR profile (so testers can always turn OFF what locks them).
    final localDiscreet = prefs.getBool('discreet_mode_local') ?? false;
    if (!mounted) return;
    setState(() {
      _discreetMode = localDiscreet || auth.isDiscreetMode;
      _sharePresence = auth.sharePresence;
      _sosNotifyGroups = auth.sosNotifyGroups;
    });
  }

  Future<void> _saveDiscreet(bool value) async {
    final auth = context.read<AuthProvider>();
    setState(() => _discreetMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('discreet_mode_local', value);
    if (value) {
      await prefs.setBool('discreet_unlocked_session', false);
    } else {
      // Turning off: clear session lock so next launch stays open.
      await prefs.setBool('discreet_unlocked_session', true);
    }
    if (!mounted) return;
    if (auth.isAuthenticated) {
      setState(() => _saving = true);
      await auth.updateProfile(isDiscreetMode: value);
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Camouflage activé. Déverrouillage : $kDiscreetUnlockCode'
              : 'Camouflage désactivé. L\'app s\'ouvrira normalement.',
        ),
      ),
    );
  }

  Future<void> _saveSharePresence(bool value) async {
    setState(() => _sharePresence = value);
    final auth = context.read<AuthProvider>();
    if (auth.isAuthenticated) {
      setState(() => _saving = true);
      await auth.updateProfile(sharePresence: value);
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSosNotifyGroups(bool value) async {
    setState(() => _sosNotifyGroups = value);
    final auth = context.read<AuthProvider>();
    if (auth.isAuthenticated) {
      setState(() => _saving = true);
      await auth.updateProfile(sosNotifyGroups: value);
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _navTile(String label, String screen, IconData icon) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, size: 20, color: AppColors.bleuFonce),
      title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => widget.onNavigate?.call(screen),
    );
  }

  Future<void> _configureDuressPin() async {
    final ctrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Code de contrainte', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '4 à 8 chiffres, différent de 1234 (déverrouillage calculatrice).',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Nouveau code', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirmer', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    final pin = ctrl.text.trim();
    final confirm = confirmCtrl.text.trim();
    ctrl.dispose();
    confirmCtrl.dispose();
    if (ok != true || !mounted) return;
    if (pin != confirm) {
      showAppSnackBar(context, 'Les codes ne correspondent pas', isError: true);
      return;
    }
    try {
      await DuressPinService().setPin(pin);
      if (mounted) showAppSnackBar(context, 'Code de contrainte enregistré');
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          e is ArgumentError ? e.message.toString() : 'Impossible d\'enregistrer ce code',
          isError: true,
        );
      }
    }
  }

  Future<String?> _askPassphrase(String title) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Phrase secrète', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.length < 6) return null;
    return result;
  }

  Future<List<Map<String, dynamic>>> _contactsAsMaps() async {
    try {
      final list = context.read<ContactsProvider>().contacts;
      return list
          .map((c) => Map<String, dynamic>.from(c))
          .where((m) => m.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer le compte ?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text('Cette action est irréversible. Toutes vos données seront effacées.',
            style: TextStyle(fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(fontSize: 13)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.rouge,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Supprimer', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _deleting = true);
    try {
      await ApiService().delete('/auth/account');
      if (mounted) widget.onLogout();
    } catch (_) {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final phone = user?['phone'] as String? ?? auth.phone ?? '+243 xxx xxx xxx';

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          Container(
            width: double.infinity,
            color: AppColors.bleuFonce,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: widget.onBack,
                  child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Paramètres',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_saving) ...[
                  const Spacer(),
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.blanc,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PROFIL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gris, letterSpacing: 1)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.bleuFonce,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(child: Text('👤', style: TextStyle(fontSize: 20))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(user?['pseudo'] as String? ?? 'Citoyen',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.bleuFonce),
                                    overflow: TextOverflow.ellipsis),
                                Text(phone, style: const TextStyle(fontSize: 11, color: AppColors.gris), overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.blanc,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('CONFIDENTIALITÉ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gris, letterSpacing: 1)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Partager ma présence', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.bleuFonce)),
                                Text('Met à jour votre position pour les alertes communautaires', style: TextStyle(fontSize: 10, color: AppColors.gris)),
                              ],
                            ),
                          ),
                          Switch(
                            value: _sharePresence,
                            onChanged: _saveSharePresence,
                            activeColor: AppColors.vert,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Alerter mes groupes en SOS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.bleuFonce)),
                                Text('Notifie les membres de vos groupes voisins lors d\'un SOS (push uniquement)', style: TextStyle(fontSize: 10, color: AppColors.gris)),
                              ],
                            ),
                          ),
                          Switch(
                            value: _sosNotifyGroups,
                            onChanged: _saveSosNotifyGroups,
                            activeColor: AppColors.orange,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.blanc,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('MODE DISCRET', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gris, letterSpacing: 1)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Camouflage calculatrice', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.bleuFonce)),
                                Text(
                                  'Désactivé par défaut. Code : $kDiscreetUnlockCode. Les SOS entrants restent toujours sonores.',
                                  style: const TextStyle(fontSize: 10, color: AppColors.gris),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _discreetMode,
                            onChanged: _saveDiscreet,
                            activeColor: AppColors.rouge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.grisClair,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Si la calculatrice s\'affiche au démarrage : tapez $kDiscreetUnlockCode puis désactivez ce commutateur.',
                              style: const TextStyle(fontSize: 10, color: AppColors.gris),
                            ),
                            const SizedBox(height: 6),
                            const Row(
                              children: [
                                Text('📖', style: TextStyle(fontSize: 14)),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text('Android : 3× Volume ↓ pour SOS discret (app ouverte)',
                                      style: TextStyle(fontSize: 10, color: AppColors.gris)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text('iOS : détection volume non disponible (limitation système)',
                                style: TextStyle(fontSize: 10, color: AppColors.gris, fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Code de contrainte', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.bleuFonce)),
                      const SizedBox(height: 4),
                      const Text(
                        'Sur la calculatrice, ce code envoie une alerte sans ouvrir l\'app. Différent du code de déverrouillage.',
                        style: TextStyle(fontSize: 10, color: AppColors.gris),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _configureDuressPin,
                              child: const Text('Configurer', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextButton(
                              onPressed: () async {
                                await DuressPinService().clearPin();
                                if (mounted) {
                                  showAppSnackBar(context, 'Code de contrainte retiré');
                                }
                              },
                              child: const Text('Retirer', style: TextStyle(fontSize: 12, color: AppColors.gris)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.blanc,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.of(context).language.toUpperCase(),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gris, letterSpacing: 1)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final code in ['fr', 'ln', 'sw', 'en'])
                            ChoiceChip(
                              label: Text({'fr': 'FR', 'ln': 'LN', 'sw': 'SW', 'en': 'EN'}[code]!),
                              selected: context.watch<LocaleProvider>().locale.languageCode == code,
                              onSelected: (_) => context.read<LocaleProvider>().setLocale(code),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.blanc,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SÉCURITÉ AVANCÉE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gris, letterSpacing: 1)),
                      const SizedBox(height: 8),
                      _navTile(AppLocalizations.of(context).safeTrip, 'trip', Icons.route),
                      _navTile('Contrôle « Tu es OK ? »', 'safety_ping', Icons.timer_outlined),
                      _navTile('Envois en attente', 'offline_queue', Icons.cloud_upload_outlined),
                      _navTile(AppLocalizations.of(context).trustZones, 'trust_zones', Icons.home_work_outlined),
                      _navTile(AppLocalizations.of(context).neighborhood, 'neighborhood', Icons.apartment),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final pass = await _askPassphrase('Phrase secrète (sauvegarde)');
                          if (pass == null || !mounted) return;
                          try {
                            final list = await _contactsAsMaps();
                            await ContactBackupService().backup(list, pass);
                            if (mounted) {
                              showAppSnackBar(context, 'Contacts sauvegardés (chiffrés)');
                            }
                          } catch (e) {
                            if (mounted) {
                              showAppSnackBar(
                                context,
                                e,
                                isError: true,
                                fallback: 'Impossible de sauvegarder les contacts.',
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                        label: const Text('Sauvegarder contacts (chiffré)', style: TextStyle(fontSize: 13)),
                      ),
                      TextButton(
                        onPressed: () async {
                          final pass = await _askPassphrase('Phrase secrète (restauration)');
                          if (pass == null || !mounted) return;
                          try {
                            final restored = await ContactBackupService().restore(pass);
                            if (mounted) {
                              showAppSnackBar(
                                context,
                                restored == null
                                    ? 'Aucune sauvegarde trouvée'
                                    : '${restored.length} contact(s) déchiffrés — réajoutez-les si besoin',
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              showAppSnackBar(
                                context,
                                e,
                                isError: true,
                                fallback: 'Impossible de restaurer les contacts.',
                              );
                            }
                          }
                        },
                        child: const Text('Restaurer contacts', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.blanc,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PREMIUM', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gris, letterSpacing: 1)),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => widget.onNavigate?.call('premium'),
                          icon: const Icon(Icons.workspace_premium_outlined, size: 16),
                          label: const Text('SafeAlert Premium', style: TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.teal,
                            side: const BorderSide(color: AppColors.teal),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.blanc,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('AIDE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gris, letterSpacing: 1)),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: widget.onHelp,
                          icon: const Icon(Icons.menu_book_outlined, size: 16),
                          label: const Text('Aide / Manuel d\'utilisation', style: TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.bleuFonce,
                            side: const BorderSide(color: Color(0xFFDDDDDD)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.blanc,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('LÉGAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gris, letterSpacing: 1)),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: widget.onPrivacy,
                          icon: const Icon(Icons.privacy_tip_outlined, size: 16),
                          label: const Text('Politique de confidentialité', style: TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.bleuFonce,
                            side: const BorderSide(color: Color(0xFFDDDDDD)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.blanc,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('COMPTE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gris, letterSpacing: 1)),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Profil : ${auth.roleLabel}',
                          style: const TextStyle(fontSize: 11, color: AppColors.gris),
                        ),
                      ),
                      if (widget.onLeader != null) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: widget.onLeader,
                            icon: const Icon(Icons.shield_outlined, size: 16),
                            label: const Text('Mode responsable', style: TextStyle(fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.bleuFonce,
                              side: const BorderSide(color: AppColors.bleuFonce),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                      if (widget.onAdmin != null) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: widget.onAdmin,
                            icon: const Icon(Icons.admin_panel_settings, size: 16),
                            label: const Text('Administration', style: TextStyle(fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.bleuFonce,
                              side: const BorderSide(color: AppColors.bleuFonce),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: auth.loading
                              ? null
                              : () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Déconnecter partout ?',
                                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                      content: const Text(
                                        'Tous vos autres appareils seront déconnectés. Cet appareil reste connecté.',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: const Text('Confirmer'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok != true || !mounted) return;
                                  final success = await auth.revokeAllOtherSessions();
                                  if (!mounted) return;
                                  showAppSnackBar(
                                    context,
                                    success
                                        ? 'Autres appareils déconnectés'
                                        : 'Impossible pour le moment. Réessayez.',
                                    isError: !success,
                                  );
                                },
                          icon: const Icon(Icons.phonelink_erase, size: 16),
                          label: const Text('Déconnecter les autres appareils', style: TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.bleuFonce,
                            side: const BorderSide(color: AppColors.bleuFonce),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: auth.loading ? null : () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Se déconnecter ?',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                content: const Text(
                                  'Vous pourrez vous reconnecter avec votre numéro.',
                                  style: TextStyle(fontSize: 12),
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Déconnexion'),
                                  ),
                                ],
                              ),
                            );
                            if (ok != true || !mounted) return;
                            await auth.logout();
                            widget.onLogout();
                          },
                          icon: const Icon(Icons.logout, size: 16),
                          label: const Text('Déconnexion', style: TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.gris,
                            side: const BorderSide(color: Color(0xFFDDDDDD)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _deleting ? null : _deleteAccount,
                          icon: _deleting
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.delete_forever, size: 16),
                          label: Text(_deleting ? 'Suppression...' : 'Supprimer le compte',
                              style: const TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.rouge,
                            side: const BorderSide(color: AppColors.rouge),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
