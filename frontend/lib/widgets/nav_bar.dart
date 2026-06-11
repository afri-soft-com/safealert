import 'package:flutter/material.dart';
import '../theme.dart';

class NavItem {
  final String id;
  final String icon;
  final String label;
  const NavItem(this.id, this.icon, this.label);
}

class NavBar extends StatelessWidget {
  final String active;
  final ValueChanged<String> onTap;
  const NavBar({super.key, required this.active, required this.onTap});

  static const items = [
    NavItem('home', '🏠', 'Accueil'),
    NavItem('map', '🗺', 'Carte'),
    NavItem('contacts', '👥', 'Confiance'),
    NavItem('annuaire', '📞', 'Urgences'),
    NavItem('dashboard', '📊', 'Stats'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.blanc,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 4),
      child: Row(
        children: items.map((item) {
          final isActive = active == item.id;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(item.id),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.icon, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: isActive ? AppColors.rouge : const Color(0xFFAAAAAA),
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
