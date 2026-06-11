import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safealert/providers/history_provider.dart';
import '../mocks.dart';

void main() {
  late FakeApiService fakeApi;
  late FakeLocalDatabase fakeDb;
  late HistoryProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeApi = FakeApiService();
    fakeDb = FakeLocalDatabase();
    provider = HistoryProvider(apiService: fakeApi, localDatabase: fakeDb);
  });

  group('fetchHistory', () {
    test('fetches history from API', () async {
      fakeApi.onGet('/history', () => {
        'data': [
          {'id': 1, 'incident_type': 'sos', 'status': 'active', 'created_at': '2025-01-01T00:00:00Z'},
        ],
      });

      await provider.fetchHistory();

      expect(provider.history.length, 1);
      expect(provider.history[0]['incident_type'], 'sos');
      expect(provider.loading, false);
      expect(provider.isOffline, false);
    });

    test('falls back to cache on error', () async {
      await fakeDb.put('history', [
        {'id': 2, 'incident_type': 'vol', 'status': 'resolved'},
      ]);

      await provider.fetchHistory();

      expect(provider.history.length, 1);
      expect(provider.history[0]['incident_type'], 'vol');
      expect(provider.isOffline, true);
    });

    test('sets empty list when cache misses on error', () async {
      await provider.fetchHistory();

      expect(provider.history, isEmpty);
      expect(provider.isOffline, false);
    });
  });

  group('cancelSOS', () {
    test('cancels SOS and refreshes', () async {
      fakeApi.onPost('/sos/1/cancel', () => ({}));
      fakeApi.onGet('/history', () => {'data': []});

      final result = await provider.cancelSOS(1);

      expect(result, true);
    });

    test('returns false on failure', () async {
      final result = await provider.cancelSOS(999);

      expect(result, false);
    });
  });

  group('statusLabel', () {
    test('returns correct labels', () {
      expect(provider.statusLabel('active'), 'Actif');
      expect(provider.statusLabel('resolved'), 'Résolu');
      expect(provider.statusLabel('false_alarm'), 'Fausse alerte');
      expect(provider.statusLabel(null), 'Inconnu');
      expect(provider.statusLabel('autre'), 'autre');
    });
  });
}
