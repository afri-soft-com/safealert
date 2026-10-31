import 'package:flutter/foundation.dart';

/// Foreground in-app alerts (socket + FCM) so the user sees an actionable
/// banner while SafeAlert is open — not only a system tray notification.
class InAppAlertService extends ChangeNotifier {
  static final InAppAlertService _instance = InAppAlertService._();
  InAppAlertService._();
  factory InAppAlertService() => _instance;

  Map<String, String>? _banner;
  DateTime? _bannerAt;

  Map<String, String>? get banner => _banner;

  static const criticalTypes = {
    'sos_alert',
    'nearby_alert',
    'group_sos',
    'group_report',
    'sector_sos',
    'trust_zone_alert',
    'false_alarm',
    'group_false_alarm',
    'group_safe',
    'safety_ping_ask',
    'safety_ping_missed',
  };

  void present(Map<String, dynamic> raw) {
    final data = <String, String>{};
    raw.forEach((k, v) {
      if (v != null) data[k.toString()] = v.toString();
    });
    final type = data['type'] ?? data['incident_type'] ?? '';
    if (type.isEmpty) data['type'] = 'sos_alert';

    final title = data['title']?.trim();
    final body = data['body']?.trim();
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      data['title'] = _defaultTitle(data['type']!);
      data['body'] = data['zone_name']?.isNotEmpty == true
          ? data['zone_name']!
          : 'Une alerte nécessite votre attention.';
    } else {
      data.putIfAbsent('title', () => _defaultTitle(data['type']!));
      data.putIfAbsent('body', () => '');
    }

    // Debounce identical bursts (socket + FCM echo within 2s).
    final now = DateTime.now();
    if (_banner != null &&
        _bannerAt != null &&
        now.difference(_bannerAt!) < const Duration(seconds: 2) &&
        _banner!['type'] == data['type'] &&
        _banner!['body'] == data['body']) {
      return;
    }
    _banner = data;
    _bannerAt = now;
    notifyListeners();
  }

  void dismiss() {
    if (_banner == null) return;
    _banner = null;
    notifyListeners();
  }

  Map<String, String>? takeForNavigation() {
    final b = _banner;
    _banner = null;
    if (b != null) notifyListeners();
    return b;
  }

  static String _defaultTitle(String type) {
    switch (type) {
      case 'group_sos':
      case 'group_report':
        return 'Alerte groupe';
      case 'trust_zone_alert':
        return 'Zone de confiance';
      case 'safety_ping_ask':
      case 'safety_ping_missed':
        return 'Safety ping';
      case 'false_alarm':
      case 'group_false_alarm':
        return 'Fausse alerte';
      case 'group_safe':
        return 'En sécurité';
      default:
        return 'Alerte SafeAlert';
    }
  }

  static bool isCritical(String? type) =>
      type != null && criticalTypes.contains(type);
}
