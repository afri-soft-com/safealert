import 'package:flutter/material.dart';
import '../services/inbox_service.dart';
import '../theme.dart';
import 'app_logo.dart';

class TopBar extends StatelessWidget {
  final String? title;
  final String? sub;
  final bool dark;
  final VoidCallback? onMenuTap;
  final VoidCallback? onBackTap;
  final VoidCallback? onNotificationsTap;
  const TopBar({
    super.key,
    this.title,
    this.sub,
    this.dark = false,
    this.onMenuTap,
    this.onBackTap,
    this.onNotificationsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: dark ? AppColors.bleuFonce : AppColors.tealDeep,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onBackTap != null) ...[
                GestureDetector(
                  onTap: onBackTap,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
                  ),
                ),
              ],
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const AppLogo(size: 28),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SafeAlert', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5), overflow: TextOverflow.ellipsis),
                    if (sub != null) Text(sub!, style: const TextStyle(color: Colors.white70, fontSize: 10), overflow: TextOverflow.ellipsis, maxLines: 2),
                  ],
                ),
              ),
              if (onNotificationsTap != null) _notificationBell(),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onMenuTap,
                child: const Icon(Icons.menu, color: Colors.white, size: 22),
              ),
            ],
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                title!,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _notificationBell() {
    return ListenableBuilder(
      listenable: InboxService(),
      builder: (context, _) {
        final n = InboxService().unread;
        final label = n > 0
            ? 'Notifications, $n non lue${n > 1 ? 's' : ''}'
            : 'Notifications';
        return Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            onTap: onNotificationsTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(left: 6, right: 4),
              child: SizedBox(
                width: 28,
                height: 28,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.notifications, color: Colors.white, size: 22),
                    if (n > 0)
                      Positioned(
                        right: -4,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE11D2E),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            n > 9 ? '9+' : '$n',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
