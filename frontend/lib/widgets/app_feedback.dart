import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/network_error.dart';

/// SnackBar homogène — jamais de message technique brut.
void showAppSnackBar(
  BuildContext context,
  Object messageOrError, {
  bool isError = false,
  String? fallback,
  Duration duration = const Duration(seconds: 3),
}) {
  final text = messageOrError is String
      ? (looksTechnical(messageOrError)
          ? (fallback ?? 'Une erreur est survenue. Réessayez.')
          : messageOrError)
      : userFacingError(messageOrError, fallback: fallback);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text, style: const TextStyle(fontSize: 12)),
      backgroundColor: isError ? AppColors.rouge : AppColors.bleuFonce,
      behavior: SnackBarBehavior.floating,
      duration: duration,
    ),
  );
}

/// Bannière d'accès refusé (écrans admin / responsable).
class AccessDeniedView extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onBack;

  const AccessDeniedView({
    super.key,
    required this.title,
    required this.message,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (onBack != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back, color: AppColors.bleuFonce),
                  ),
                ),
              const Spacer(),
              const Icon(Icons.lock_outline, size: 48, color: AppColors.gris),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.bleuFonce,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.gris, height: 1.4),
              ),
              const Spacer(),
              if (onBack != null)
                ElevatedButton(
                  onPressed: onBack,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.bleuFonce,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Retour'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
