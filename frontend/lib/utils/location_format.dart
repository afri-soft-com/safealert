/// Format lieu + coordonnées (FR, sans jargon).
class LocationFormat {
  static const approxLabel = 'Position approximative';
  static const resolvingLabel = 'Lieu en cours de résolution';

  /// Coordonnées affichables, ex. `4.3210, 15.1234`.
  static String formatCoords(num? lat, num? lng, {int precision = 4}) {
    if (lat == null || lng == null) return '';
    final la = lat.toDouble();
    final ln = lng.toDouble();
    if (la.abs() < 0.0001 && ln.abs() < 0.0001) return '';
    return '${la.toStringAsFixed(precision)}, ${ln.toStringAsFixed(precision)}';
  }

  /// Nom du lieu, ou libellé de repli clair.
  static String placeName({
    String? zoneName,
    bool approximate = false,
  }) {
    final z = zoneName?.trim();
    if (z != null && z.isNotEmpty) return z;
    if (approximate) return approxLabel;
    return resolvingLabel;
  }

  /// Ligne unique : « Gombe · 4.3210, 15.1234 » ou repli + coords.
  static String displayLine({
    String? zoneName,
    num? lat,
    num? lng,
    bool approximate = false,
  }) {
    final place = placeName(zoneName: zoneName, approximate: approximate);
    final coords = formatCoords(lat, lng);
    if (coords.isEmpty) return place;
    return '$place · $coords';
  }

  /// Depuis un objet incident / SOS API.
  static String fromIncident(
    Map<String, dynamic>? data, {
    bool approximate = false,
  }) {
    if (data == null) {
      return placeName(approximate: approximate);
    }
    return displayLine(
      zoneName: data['zone_name']?.toString(),
      lat: data['lat'] as num?,
      lng: data['lng'] as num?,
      approximate: approximate,
    );
  }
}
