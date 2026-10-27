import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_service.dart';
import '../utils/location_format.dart';

/// Partage système + raccourci WhatsApp (FR, sans jargon).
class ShareHelper {
  /// Public HTTPS origin derived from API base (strip `/api` and any path).
  /// Used for QR codes that phone cameras can open — must NEVER include `/api`
  /// or Safari hits the JSON 404 handler (`Page introuvable`).
  static String get publicWebOrigin {
    const fallback = 'https://safealert-api.onrender.com';
    final api = ApiService.baseUrl; // e.g. https://safealert-api.onrender.com/api
    final uri = Uri.tryParse(api);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return fallback;
    final port = uri.hasPort && uri.port != 80 && uri.port != 443
        ? ':${uri.port}'
        : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  static String groupInviteUrl(String code) {
    final c = code.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (c.length < 6) {
      // Avoid generating https://…/g/ which 404s as JSON in Safari.
      return publicWebOrigin;
    }
    return '$publicWebOrigin/g/$c';
  }

  static Future<void> shareText(String text, {String? subject}) async {
    await Share.share(text, subject: subject ?? 'SafeAlert');
  }

  static Future<void> shareWhatsApp(String text) async {
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(text)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await shareText(text);
    }
  }

  static String sosMessage({
    required double lat,
    required double lng,
    String? pseudo,
    String? zoneName,
    bool approximate = false,
  }) {
    final maps = 'https://maps.google.com/?q=$lat,$lng';
    final who = pseudo != null && pseudo.isNotEmpty ? '$pseudo — ' : '';
    final where = LocationFormat.displayLine(
      zoneName: zoneName,
      lat: lat,
      lng: lng,
      approximate: approximate,
    );
    return '${who}🚨 Alerte SafeAlert ! Lieu : $where. Carte : $maps';
  }

  static String tripMessage(String shareUrl, {String? dest}) {
    final destPart = dest != null && dest.isNotEmpty ? ' vers $dest' : '';
    return 'Suivez mon trajet SafeAlert$destPart (carte en lecture seule) : $shareUrl';
  }

  static String inviteMessage(String shareUrl, String code) {
    return 'Rejoins mon cercle SafeAlert avec le code $code : $shareUrl';
  }

  static String groupInviteMessage(String code, {String? groupName}) {
    final name = groupName != null ? ' « $groupName »' : '';
    final url = groupInviteUrl(code);
    return 'Rejoins mon groupe SafeAlert$name avec le code $code : $url';
  }
}
