import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../widgets/status_bar.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../screens/calculator_screen.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onLogout;
  final VoidCallback? onPrivacy;
  const SettingsScreen({super.key, required this.onBack, required this.onLogout, this.onPrivacy});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _discreetMode = false;
  bool _sharePresence = true;
  bool _deleting = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPrefs());
  }

  void _loadPrefs() {
    final auth = context.read<AuthProvider>();
    setState(() {
      _discreetMode = auth.isDiscreetMode;
      _sharePresence = auth.sharePresence;
    });
  }

  Future<void> _saveDiscreet(bool value) async {
    final auth = context.read<AuthProvider>();
    setState(() => _discreetMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('discreet_mode_local', value);
    if (value) {
      await prefs.setBool('discreet_unlocked_session', false);
    }
    if (!mounted) return;
    if (auth.isAuthenticated) {
      setState(() => _saving = true);
      await auth.updateProfile(isDiscreetMode: value);
      if (mounted) setState(() => _saving = false);
    }
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
                const Text('Paramètres', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user?['pseudo'] as String? ?? 'Citoyen',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.bleuFonce)),
                              Text(phone, style: const TextStyle(fontSize: 11, color: AppColors.gris)),
                            ],
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
                                Text('Code déverrouillage : $kDiscreetUnlockCode', style: const TextStyle(fontSize: 10, color: AppColors.gris)),
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
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('📖', style: TextStyle(fontSize: 14)),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text('Android : 3× Volume ↓ pour SOS discret (app ouverte)',
                                      style: TextStyle(fontSize: 10, color: AppColors.gris)),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                            Text('iOS : détection volume non disponible (limitation système)',
                                style: TextStyle(fontSize: 10, color: AppColors.gris, fontStyle: FontStyle.italic)),
                          ],
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
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: auth.loading ? null : () async {
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
