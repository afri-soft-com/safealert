import 'package:flutter/foundation.dart';

class IncidentTypeDef {
  final String slug;
  final String labelFr;

  const IncidentTypeDef({required this.slug, required this.labelFr});

  factory IncidentTypeDef.fromJson(Map<String, dynamic> json) {
    final slug = (json['slug'] ?? json['incident_type'] ?? '').toString();
    final label = (json['label_fr'] ?? json['label'] ?? slug).toString();
    return IncidentTypeDef(slug: slug, labelFr: label);
  }

  Map<String, dynamic> toJson() => {'slug': slug, 'label_fr': labelFr};
}

/// Offline fallback when GET /incident-types is empty or unreachable.
const kFallbackIncidentTypes = <IncidentTypeDef>[
  IncidentTypeDef(slug: 'agression', labelFr: 'Agression'),
  IncidentTypeDef(slug: 'vol', labelFr: 'Vol'),
  IncidentTypeDef(slug: 'accident', labelFr: 'Accident'),
  IncidentTypeDef(slug: 'incendie', labelFr: 'Incendie'),
  IncidentTypeDef(slug: 'suspect', labelFr: 'Présence suspecte'),
  IncidentTypeDef(slug: 'autre', labelFr: 'Autre'),
];

/// Report types that read as criminal-activity reports. App Review (guideline
/// 2.1) only allows those with a law-enforcement partner, which we do not have,
/// so the iOS build does not offer them.
const kCrimeIncidentSlugs = {'agression', 'vol', 'suspect'};

/// Types the user can pick to file a report on this platform.
List<IncidentTypeDef> reportableIncidentTypes(
  List<IncidentTypeDef> catalog, {
  TargetPlatform? platform,
}) {
  final target = platform ?? defaultTargetPlatform;
  if (kIsWeb || target != TargetPlatform.iOS) return catalog;
  return catalog.where((t) => !kCrimeIncidentSlugs.contains(t.slug)).toList();
}

/// SOS labels stay hardcoded — SOS is not a report-form type.
String incidentTypeLabel(String? slug, {List<IncidentTypeDef>? catalog}) {
  if (slug == null || slug.isEmpty) return 'Signalement';
  switch (slug) {
    case 'sos':
      return 'Alerte SOS';
    case 'sos_discret':
      return 'SOS Discret';
  }
  if (catalog != null) {
    for (final t in catalog) {
      if (t.slug == slug) return t.labelFr;
    }
  }
  for (final t in kFallbackIncidentTypes) {
    if (t.slug == slug) return t.labelFr;
  }
  return slug;
}
