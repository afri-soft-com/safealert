import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';

class SplashScreen extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback? onGuest;
  const SplashScreen({super.key, required this.onStart, this.onGuest});

  static const _splashAsset = 'assets/branding/splash.png';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            _splashAsset,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: AppColors.tealDeep),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.tealDeep.withValues(alpha: 0.35),
                  AppColors.tealDeep.withValues(alpha: 0.82),
                  const Color(0xFF041F1F).withValues(alpha: 0.94),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AppLogo(size: 112, showShadow: true),
                    const SizedBox(height: 20),
                    const Text(
                      'SafeAlert',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sécurité citoyenne',
                      style: TextStyle(
                        color: AppColors.mint.withValues(alpha: 0.9),
                        fontSize: 14,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 36),
                    const Text(
                      'Alertez votre communauté.\nRestez en sécurité. Ensemble.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.55),
                    ),
                    const SizedBox(height: 44),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: onStart,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.rouge,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(vertical: 15),
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
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        child: const Text('Se connecter', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    if (onGuest != null) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: onGuest,
                        child: const Text(
                          'Explorer la carte sans compte',
                          style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      'Vos données sont protégées et anonymisées',
                      style: TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
