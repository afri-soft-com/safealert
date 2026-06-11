import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safealert/providers/incident_provider.dart';
import '../mocks.dart';

void main() {
  late FakeApiService fakeApi;
  late FakeLocalDatabase fakeDb;
  late IncidentProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeApi = FakeApiService();
    fakeDb = FakeLocalDatabase();
    provider = IncidentProvider(apiService: fakeApi, localDatabase: fakeDb);
  });

  group('fetchIncidents', () {
    test('fetches and caches incidents', () async {
      fakeApi.onGet('/map/incidents?limit=100&hours=24', () => {
        'data': [
          {'id': 1, 'incident_type': 'agression', 'lat': -4.3, 'lng': 15.3},
        ],
      });

      await provider.fetchIncidents();

      expect(provider.incidents.length, 1);
      expect(provider.incidents[0]['incident_type'], 'agression');
      expect(provider.loading, false);
      expect(provider.isOffline, false);

      final cached = await fakeDb.get('incidents');
      expect(cached, isNotNull);
    });

    test('falls back to cache on error', () async {
      await fakeDb.put('incidents', [
        {'id': 1, 'incident_type': 'vol'},
      ]);

      await provider.fetchIncidents();

      expect(provider.incidents.length, 1);
      expect(provider.incidents[0]['incident_type'], 'vol');
      expect(provider.isOffline, true);
    });

    test('sets empty list when cache misses on error', () async {
      await provider.fetchIncidents();

      expect(provider.incidents, isEmpty);
      expect(provider.isOffline, false);
    });
  });

  group('reportIncident', () {
    test('posts incident and refreshes list', () async {
      fakeApi.onPost('/map/incidents', () => {'id': 1, 'status': 'active'});
      fakeApi.onGet('/map/incidents?limit=100&hours=24', () => {'data': []});

      await provider.reportIncident(-4.3, 15.3, 'vol', anonymous: true);

      expect(fakeApi.lastBody!['incident_type'], 'vol');
      expect(fakeApi.lastBody!['is_anonymous'], true);
    });
  });

  group('fetchStats', () {
    test('fetches and caches stats', () async {
      fakeApi.onGet('/map/stats', () => {'total': 42, 'resolved': 10});

      await provider.fetchStats();

      expect(provider.stats, isNotNull);
      expect(provider.stats!['total'], 42);
    });

    test('falls back to cache on error', () async {
      await fakeDb.put('stats', {'total': 10, 'resolved': 5});

      await provider.fetchStats();

      expect(provider.stats!['total'], 10);
      expect(provider.isOffline, true);
    });
  });

  group('fetchHeatmap', () {
    test('fetches heatmap data', () async {
      fakeApi.onGet('/map/heatmap?days=30', () => {
        'zones': [
          {'lat': -4.3, 'lng': 15.3, 'density': 0.8},
        ],
      });

      await provider.fetchHeatmap();

      expect(provider.heatmap.length, 1);
      expect(provider.heatmap[0]['density'], 0.8);
    });

    test('uses custom days parameter', () async {
      fakeApi.onGet('/map/heatmap?days=7', () => {'zones': []});

      await provider.fetchHeatmap(days: 7);

      expect(fakeApi.lastPath, '/map/heatmap?days=7');
    });

    test('falls back to cache on error', () async {
      await fakeDb.put('heatmap', [
        {'lat': -4.3, 'density': 0.5},
      ]);

      await provider.fetchHeatmap();

      expect(provider.heatmap.length, 1);
      expect(provider.isOffline, true);
    });
  });

  group('triggerSOS', () {
    test('triggers SOS and returns response', () async {
      fakeApi.onPost('/sos/trigger', () => {'incident': {'id': 1}});

      final result = await provider.triggerSOS(-4.3, 15.3);

      expect(result, isNotNull);
      expect(result!['incident']['id'], 1);
    });

    test('returns null on failure', () async {
      final result = await provider.triggerSOS(-4.3, 15.3);

      expect(result, isNull);
    });
  });

  group('cancelSOS', () {
    test('cancels and returns true', () async {
      fakeApi.onPost('/sos/cancel', () => {'message': 'AnnulÃ©'});

      final result = await provider.cancelSOS();

      expect(result, true);
    });

    test('returns false on failure', () async {
      final result = await provider.cancelSOS();

      expect(result, false);
    });
  });

  group('verifyIncident', () {
    test('verifies and refreshes incidents', () async {
      fakeApi.onPost('/map/incidents/1/verify', () => {'message': 'ConfirmÃ©'});
      fakeApi.onGet('/map/incidents?limit=100&hours=24', () => {'data': []});

      final result = await provider.verifyIncident(1);

      expect(result, true);
    });

    test('returns false on failure', () async {
      final result = await provider.verifyIncident(999);

      expect(result, false);
    });
  });
}
