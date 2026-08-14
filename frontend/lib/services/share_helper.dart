import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/location_format.dart';

/// Partage système + raccourci WhatsApp (FR, sans jargon).
class ShareHelper {
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
    return 'Rejoins mon groupe SafeAlert$name avec le code $code '
        '(safealert://group/$code)';
  }
}
