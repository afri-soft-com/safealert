import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safealert/services/low_battery_watcher.dart';
import 'package:safealert/services/refuge_service.dart';

void main() {
  group('LowBatteryWatcher.shouldReport', () {
    test('reports at 5 % while discharging', () {
      expect(
        LowBatteryWatcher.shouldReport(level: 5, state: BatteryState.discharging),
        isTrue,
      );
    });

    test('ignores a phone that is charging', () {
      expect(
        LowBatteryWatcher.shouldReport(level: 3, state: BatteryState.charging),
        isFalse,
      );
    });

    test('ignores levels above the threshold', () {
      expect(
        LowBatteryWatcher.shouldReport(level: 6, state: BatteryState.discharging),
        isFalse,
      );
    });

    test('waits 30 min between two reports', () {
      final now = DateTime(2026, 11, 20, 12);
      expect(
        LowBatteryWatcher.shouldReport(
          level: 4,
          state: BatteryState.discharging,
          lastSent: now.subtract(const Duration(minutes: 10)),
          now: now,
        ),
        isFalse,
      );
      expect(
        LowBatteryWatcher.shouldReport(
          level: 4,
          state: BatteryState.discharging,
          lastSent: now.subtract(const Duration(minutes: 31)),
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('Refuge', () {
    test('parses the API row, numbers sent as strings included', () {
      final r = Refuge.fromJson({
        'id': 'r1',
        'name': 'Centre de santé',
        'category': 'hospital',
        'lat': '-4.32',
        'lng': 15.31,
        'phone': '  ',
        'open_24h': true,
        'distance_km': '0.42',
      });
      expect(r.lat, -4.32);
      expect(r.phone, isNull);
      expect(r.open24h, isTrue);
      expect(r.distanceKm, closeTo(0.42, 1e-9));
    });

    test('formats distances', () {
      expect(RefugeService.formatDistance(0.42), '420 m');
      expect(RefugeService.formatDistance(2.345), '2.3 km');
    });

    test('only leaders, agents and admins can add places', () {
      expect(RefugeService.canEdit('citizen'), isFalse);
      expect(RefugeService.canEdit('leader'), isTrue);
    });
  });
}
