import 'package:flutter/material.dart';
import '../theme.dart';

class StatusBar extends StatelessWidget {
  final bool dark;
  const StatusBar({super.key, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: dark ? AppColors.bleuFonce : AppColors.rouge,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('9:41', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
          const Text('●●● WiFi 🔋', style: TextStyle(color: Colors.white, fontSize: 10)),
        ],
      ),
    );
  }
}
