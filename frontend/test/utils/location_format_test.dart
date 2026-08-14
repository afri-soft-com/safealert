import 'package:flutter_test/flutter_test.dart';
import 'package:safealert/utils/location_format.dart';

void main() {
  group('LocationFormat', () {
    test('formats coords with 4 decimals', () {
      expect(LocationFormat.formatCoords(-4.32171, 15.31234), '-4.3217, 15.3123');
    });

    test('uses place name when present', () {
      expect(
        LocationFormat.displayLine(zoneName: 'Gombe', lat: -4.32, lng: 15.31),
        'Gombe · -4.3200, 15.3100',
      );
    });

    test('falls back to resolving label', () {
      expect(
        LocationFormat.placeName(),
        LocationFormat.resolvingLabel,
      );
    });

    test('falls back to approximate label', () {
      expect(
        LocationFormat.placeName(approximate: true),
        LocationFormat.approxLabel,
      );
    });
  });
}
