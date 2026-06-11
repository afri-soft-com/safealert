import 'package:flutter/material.dart';
import '../theme.dart';
import 'app_logo.dart';

class TopBar extends StatelessWidget {
  final String? title;
  final String? sub;
  final bool dark;
  final VoidCallback? onMenuTap;
  const TopBar({super.key, this.title, this.sub, this.dark = false, this.onMenuTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: dark ? AppColors.bleuFonce : AppColors.rouge,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const AppLogo(size: 28),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SafeAlert', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  if (sub != null) Text(sub!, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                ],
              ),
              const Spacer(),
              GestureDetector(
                onTap: onMenuTap,
                child: const Icon(Icons.menu, color: Colors.white, size: 22),
              ),
            ],
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(title!, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
