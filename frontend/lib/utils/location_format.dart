/// Format lieu + coordonnées (FR, sans jargon).
class LocationFormat {
  static const approxLabel = 'Position approximative';
  static const resolvingLabel = 'Lieu en cours de résolution';

  /// Parse lat/lng from API (num or numeric string).
  static num? parseCoord(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    if (value is String) return num.tryParse(value.trim());
    return null;
  }

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
  /// Sans nom de zone mais avec GPS : affiche seulement les coordonnées.
  static String displayLine({
    String? zoneName,
    num? lat,
    num? lng,
    bool approximate = false,
  }) {
    final z = zoneName?.trim();
    final hasPlace = z != null && z.isNotEmpty;
    final coords = formatCoords(lat, lng);
    if (hasPlace && coords.isNotEmpty) return '$z · $coords';
    if (hasPlace) return z;
    if (coords.isNotEmpty) {
      return approximate ? '$approxLabel · $coords' : coords;
    }
    return placeName(zoneName: zoneName, approximate: approximate);
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
      lat: parseCoord(data['lat']),
      lng: parseCoord(data['lng']),
      approximate: approximate,
    );
  }
}
