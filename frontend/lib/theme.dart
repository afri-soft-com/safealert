import 'package:flutter/material.dart';

class AppColors {
  static const rouge = Color(0xFFCC1C1C);
  static const rougeDark = Color(0xFF991515);
  static const rougeLight = Color(0xFFFCEBEB);
  static const bleuFonce = Color(0xFF0D1B2A);
  /// Brand teal (logo / splash)
  static const teal = Color(0xFF0B6E6E);
  static const tealDeep = Color(0xFF063D3D);
  static const mint = Color(0xFFB8E0D2);
  static const bleu = Color(0xFF185FA5);
  static const gris = Color(0xFF4A4A6A);
  static const grisClair = Color(0xFFF5F5F7);
  static const orange = Color(0xFFE86A1A);
  static const vert = Color(0xFF3B6D11);
  static const vertClair = Color(0xFFEAF3DE);
  static const blanc = Color(0xFFFFFFFF);
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      scaffoldBackgroundColor: AppColors.grisClair,
      colorScheme: ColorScheme.light(
        primary: AppColors.rouge,
        secondary: AppColors.bleuFonce,
        surface: AppColors.blanc,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.rouge,
        foregroundColor: AppColors.blanc,
        elevation: 0,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.blanc,
        selectedItemColor: AppColors.rouge,
        unselectedItemColor: Color(0xFFAAAAAA),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.rouge,
          foregroundColor: AppColors.blanc,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 40),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
