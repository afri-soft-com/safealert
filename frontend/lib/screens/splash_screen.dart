import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';

class SplashScreen extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback? onGuest;
  const SplashScreen({super.key, required this.onStart, this.onGuest});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bleuFonce,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppLogo(size: 120, showShadow: true),
              const SizedBox(height: 24),
              const Text('SafeAlert', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const SizedBox(height: 4),
              const Text('SÉCURITÉ CITOYENNE', style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 40),
              const Text('Alertez votre communauté.\nRestez en sécurité. Ensemble.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6)),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onStart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.rouge,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Commencer', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onStart,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white60,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Se connecter', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 12),
              if (onGuest != null)
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: onGuest,
                    child: const Text('Explorer la carte sans compte',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
              const SizedBox(height: 20),
              const Text('Vos données sont protégées et anonymisées',
                style: TextStyle(color: Colors.white30, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}
