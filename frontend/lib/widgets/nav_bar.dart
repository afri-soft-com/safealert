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
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: AppColors.blanc,
      elevation: 6,
      shadowColor: Colors.black12,
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, 6, 0, 4 + (bottom > 0 ? bottom * 0.35 : 0)),
        child: Row(
          children: items.map((item) {
            final isActive = active == item.id;
            return Expanded(
              child: InkWell(
                onTap: () => onTap(item.id),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: isActive ? AppColors.teal.withValues(alpha: 0.12) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(item.icon, style: const TextStyle(fontSize: 16)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          color: isActive ? AppColors.teal : const Color(0xFF9AA3AF),
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(top: 3),
                        height: 2.5,
                        width: isActive ? 18 : 0,
                        decoration: BoxDecoration(
                          color: AppColors.teal,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
