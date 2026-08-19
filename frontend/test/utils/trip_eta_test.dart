import 'package:flutter_test/flutter_test.dart';
import 'package:safealert/utils/trip_eta.dart';

void main() {
  test('walk is slower than moto over the same distance', () {
    const oLat = -4.3276;
    const oLng = 15.3136;
    const dLat = -4.3500;
    const dLng = 15.3500;
    final walk = estimateTripEtaMinutes(
      originLat: oLat,
      originLng: oLng,
      destLat: dLat,
      destLng: dLng,
      mode: TripTransportMode.walk,
    );
    final moto = estimateTripEtaMinutes(
      originLat: oLat,
      originLng: oLng,
      destLat: dLat,
      destLng: dLng,
      mode: TripTransportMode.moto,
    );
    expect(walk, greaterThan(moto));
    expect(moto, greaterThanOrEqualTo(5));
  });
}
