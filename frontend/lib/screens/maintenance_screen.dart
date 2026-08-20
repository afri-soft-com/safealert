import 'package:flutter/material.dart';
import '../theme.dart';

/// Full-screen maintenance gate (production-facing, no technical jargon).
class MaintenanceScreen extends StatelessWidget {
  final String message;
  final VoidCallback onSuperAdminLogin;
  final VoidCallback onAnnuaire;
  final VoidCallback onSos;

  const MaintenanceScreen({
    super.key,
    required this.message,
    required this.onSuperAdminLogin,
    required this.onAnnuaire,
    required this.onSos,
  });

  @override
  Widget build(BuildContext context) {
    final body = message.trim().isEmpty
        ? 'Nous effectuons une mise à jour de la plateforme. Le service sera de retour très bientôt.'
        : message;

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.teal, AppColors.tealDeep, Color(0xFF042828)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
            child: Column(
              children: [
                const Spacer(),
                const Text(
                  'Maintenance en cours',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Text(
                    'Merci de votre patience · Équipe SafeAlert',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 32),
                OutlinedButton(
                  onPressed: onAnnuaire,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: const Text('Annuaire d\'urgence'),
                ),
                TextButton(
                  onPressed: onSos,
                  child: const Text('SOS', style: TextStyle(color: Colors.white70)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onSuperAdminLogin,
                  child: const Text(
                    'Connexion super administrateur →',
                    style: TextStyle(
                      color: Color(0xFFE8B84A),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
