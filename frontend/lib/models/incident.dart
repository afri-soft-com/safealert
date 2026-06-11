class Incident {
  final String id;
  final String incidentType;
  final String? description;
  final double lat;
  final double lng;
  final String severity;
  final String status;
  final int verifiedBy;
  final bool isAnonymous;
  final String? reporter;
  final DateTime createdAt;

  Incident({
    required this.id,
    required this.incidentType,
    this.description,
    required this.lat,
    required this.lng,
    required this.severity,
    required this.status,
    this.verifiedBy = 0,
    this.isAnonymous = false,
    this.reporter,
    required this.createdAt,
  });

  factory Incident.fromJson(Map<String, dynamic> json) {
    return Incident(
      id: json['id'] as String,
      incidentType: json['incident_type'] as String? ?? 'sos',
      description: json['description'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      severity: json['severity'] as String? ?? 'alert',
      status: json['status'] as String? ?? 'active',
      verifiedBy: json['verified_by'] as int? ?? 0,
      isAnonymous: json['is_anonymous'] as bool? ?? false,
      reporter: json['reporter'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
