import 'package:latlong2/latlong.dart';

/// Moyen de transport pour estimer la durée d'un trajet sécurisé.
enum TripTransportMode { walk, moto, car }

extension TripTransportModeX on TripTransportMode {
  String get apiValue {
    switch (this) {
      case TripTransportMode.walk:
        return 'walk';
      case TripTransportMode.moto:
        return 'moto';
      case TripTransportMode.car:
        return 'car';
    }
  }

  String get label {
    switch (this) {
      case TripTransportMode.walk:
        return 'À pied';
      case TripTransportMode.moto:
        return 'Moto';
      case TripTransportMode.car:
        return 'Véhicule';
    }
  }

  /// Vitesse moyenne urbaine (Kinshasa / grandes villes RDC).
  double get kmPerHour {
    switch (this) {
      case TripTransportMode.walk:
        return 5;
      case TripTransportMode.moto:
        return 28;
      case TripTransportMode.car:
        return 22;
    }
  }
}

int estimateTripEtaMinutes({
  required double originLat,
  required double originLng,
  required double destLat,
  required double destLng,
  required TripTransportMode mode,
}) {
  const distance = Distance();
  final km = distance.as(
    LengthUnit.Kilometer,
    LatLng(originLat, originLng),
    LatLng(destLat, destLng),
  );
  if (km <= 0) return 1;
  final minutes = (km / mode.kmPerHour * 60).ceil();
  if (minutes < 1) return 1;
  if (minutes > 24 * 60) return 24 * 60;
  return minutes;
}
