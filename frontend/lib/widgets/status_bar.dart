import 'package:flutter/material.dart';
import '../theme.dart';

/// Top safe-area inset only (no fake clock / Wi‑Fi chrome).
class StatusBar extends StatelessWidget {
  final bool dark;
  const StatusBar({super.key, this.dark = false});

  @override
  Widget build(BuildContext context) {
    // Use padding only — when AppShell zeros padding.top under a system
    // banner, we must collapse (do not fall back to viewPadding or a second
    // notch strip appears under the update/alert banner on Android).
    final top = MediaQuery.paddingOf(context).top;
    if (top <= 0) return const SizedBox.shrink();
    return ColoredBox(
      color: dark ? AppColors.bleuFonce : AppColors.tealDeep,
      child: SizedBox(height: top, width: double.infinity),
    );
  }
}
