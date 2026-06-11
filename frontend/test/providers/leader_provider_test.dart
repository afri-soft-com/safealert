import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safealert/providers/leader_provider.dart';
import '../mocks.dart';

void main() {
  late FakeApiService fakeApi;
  late FakeLocalDatabase fakeDb;
  late LeaderProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeApi = FakeApiService();
    fakeDb = FakeLocalDatabase();
    provider = LeaderProvider(apiService: fakeApi, localDatabase: fakeDb);
  });

  group('fetchSectorIncidents', () {
    test('fetches incidents from API', () async {
      fakeApi.onGet('/leader/sector/incidents', () => {
        'data': [
          {'id': 'i1', 'incident_type': 'agression', 'status': 'active'},
          {'id': 'i2', 'incident_type': 'vol', 'status': 'resolved'},
        ],
      });

      await provider.fetchSectorIncidents();

      expect(provider.incidents.length, 2);
      expect(provider.incidents[0]['incident_type'], 'agression');
      expect(provider.loading, false);
      expect(provider.isOffline, false);
    });

    test('falls back to cache on error', () async {
      await fakeDb.put('sector_incidents', [
        {'id': 'i3', 'incident_type': 'incendie'},
      ]);

      await provider.fetchSectorIncidents();

      expect(provider.incidents.length, 1);
      expect(provider.incidents[0]['incident_type'], 'incendie');
      expect(provider.isOffline, true);
    });

    test('sets empty list when cache misses on error', () async {
      await provider.fetchSectorIncidents();

      expect(provider.incidents, isEmpty);
      expect(provider.isOffline, false);
    });
  });

  group('fetchSectorStats', () {
    test('fetches stats from API', () async {
      fakeApi.onGet('/leader/sector/stats', () => {
        'total': 50,
        'resolved': 30,
        'by_type': {'agression': 20, 'vol': 15},
      });

      await provider.fetchSectorStats();

      expect(provider.stats, isNotNull);
      expect(provider.stats!['total'], 50);
      expect(provider.stats!['by_type']['agression'], 20);
    });

    test('falls back to cache on error', () async {
      await fakeDb.put('sector_stats', {'total': 10, 'resolved': 5});

      await provider.fetchSectorStats();

      expect(provider.stats!['total'], 10);
      expect(provider.isOffline, true);
    });
  });

  group('resolveIncident', () {
    test('resolves and refreshes incidents and stats', () async {
      fakeApi.onPut('/leader/sector/incidents/i1/resolve', () => {'message': 'RÃ©solu'});
      fakeApi.onGet('/leader/sector/incidents', () => {'data': []});
      fakeApi.onGet('/leader/sector/stats', () => {'total': 0});

      final result = await provider.resolveIncident('i1');

      expect(result, true);
    });

    test('returns false on failure', () async {
      final result = await provider.resolveIncident('i999');

      expect(result, false);
    });
  });

  group('acknowledgeIncident', () {
    test('acknowledges and refreshes', () async {
      fakeApi.onPut('/leader/sector/incidents/i1/acknowledge', () => {'message': 'OK'});
      fakeApi.onGet('/leader/sector/incidents', () => {'data': []});
      fakeApi.onGet('/leader/sector/stats', () => {'total': 0});

      final result = await provider.acknowledgeIncident('i1');

      expect(result, true);
    });
  });
}
