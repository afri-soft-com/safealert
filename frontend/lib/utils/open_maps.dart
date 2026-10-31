import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the platform maps / navigation app for [lat],[lng].
Future<bool> openExternalMaps(
  double lat,
  double lng, {
  String? label,
}) async {
  final qLabel = (label != null && label.trim().isNotEmpty)
      ? Uri.encodeComponent(label.trim())
      : '$lat,$lng';
  final candidates = <Uri>[
    Uri.parse('google.navigation:q=$lat,$lng'),
    Uri.parse('geo:$lat,$lng?q=$lat,$lng($qLabel)'),
    Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    ),
    Uri.parse('https://maps.google.com/?q=$lat,$lng'),
    Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    ),
  ];
  for (final uri in candidates) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {}
  }
  return false;
}

Future<void> openExternalMapsOrSnack(
  BuildContext context,
  double? lat,
  double? lng, {
  String? label,
}) async {
  if (lat == null || lng == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Position indisponible pour l’itinéraire')),
      );
    }
    return;
  }
  final ok = await openExternalMaps(lat, lng, label: label);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Impossible d’ouvrir la carte')),
    );
  }
}
