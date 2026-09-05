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
