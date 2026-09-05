import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safealert/providers/incident_provider.dart';
import '../mocks.dart';

void main() {
  late FakeApiService fakeApi;
  late FakeLocalDatabase fakeDb;
  late FakeAlertSoundService fakeSounds;
  late IncidentProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeApi = FakeApiService();
    fakeDb = FakeLocalDatabase();
    fakeSounds = FakeAlertSoundService();
    provider = IncidentProvider(
      apiService: fakeApi,
      localDatabase: fakeDb,
      alertSoundService: fakeSounds,
    );
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

    test('passes severity filter to API', () async {
      final path =
          '/map/incidents?limit=100&hours=24&severity=${Uri.encodeQueryComponent('danger,vigilance')}';
      fakeApi.onGet(path, () => {
        'data': [
          {'id': 1, 'incident_type': 'agression', 'severity': 'danger'},
        ],
      });

      await provider.fetchIncidents(severities: ['vigilance', 'danger']);

      expect(fakeApi.lastPath, path);
      expect(provider.incidents.length, 1);
    });

    test('skips API when severity filter is empty', () async {
      await provider.fetchIncidents(severities: []);

      expect(fakeApi.lastPath, isNull);
      expect(provider.incidents, isEmpty);
      expect(provider.loading, false);
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
      expect(fakeSounds.playSosAlertCalls, 0);
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

    test('passes time slot parameter', () async {
      fakeApi.onGet('/map/heatmap?days=30&slot=evening', () => {'zones': []});

      await provider.fetchHeatmap(slot: 'evening');

      expect(fakeApi.lastPath, '/map/heatmap?days=30&slot=evening');
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
    test('triggers SOS without siren on the sender device', () async {
      fakeApi.onPost('/sos/trigger', () => {'incident': {'id': 1}});

      final result = await provider.triggerSOS(-4.3, 15.3);

      expect(result, isNotNull);
      expect(result!['incident']['id'], 1);
      expect(fakeSounds.playSosAlertCalls, 0);
      expect(fakeSounds.feedbackDiscreteCalls, 0);
    });

    test('plays discrete feedback instead of siren for sos_discret', () async {
      fakeApi.onPost('/sos/trigger', () => {'incident': {'id': 2}});

      final result = await provider.triggerSOS(-4.3, 15.3, type: 'sos_discret');

      expect(result, isNotNull);
      expect(fakeSounds.playSosAlertCalls, 0);
      expect(fakeSounds.feedbackDiscreteCalls, 1);
    });

    test('queues SOS offline on failure without siren', () async {
      final result = await provider.triggerSOS(-4.3, 15.3);

      expect(result, isNotNull);
      expect(result!['queued'], true);
      expect(provider.isOffline, true);
      expect(fakeSounds.playSosAlertCalls, 0);
      final pending = await fakeDb.listPendingSos();
      expect(pending, isNotEmpty);
    });
  });

  group('handleSosAlert', () {
    test('plays siren for incoming SOS from another user', () {
      fakeApi.onGet('/map/incidents?limit=100&hours=24', () => {'data': []});
      provider.handleSosAlert({'id': 'x', 'user_id': 'other-user'});
      expect(fakeSounds.playSosAlertCalls, 1);
    });

    test('does not play siren for own SOS echo', () {
      provider = IncidentProvider(
        apiService: fakeApi,
        localDatabase: fakeDb,
        alertSoundService: fakeSounds,
        currentUserId: () => 'me',
      );
      fakeApi.onGet('/map/incidents?limit=100&hours=24', () => {'data': []});
      provider.handleSosAlert({'id': 'x', 'user_id': 'me'});
      expect(fakeSounds.playSosAlertCalls, 0);
    });

    test('does not play siren for socket echo of just-sent SOS', () async {
      fakeApi.onPost('/sos/trigger', () => {'incident': {'id': 42}});
      fakeApi.onGet('/map/incidents?limit=100&hours=24', () => {'data': []});

      await provider.triggerSOS(-4.3, 15.3);
      expect(fakeSounds.playSosAlertCalls, 0);

      provider.handleSosAlert({'id': '42'});
      expect(fakeSounds.playSosAlertCalls, 0);
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

  group('fetchIncidentTypes', () {
    test('loads catalog from API', () async {
      fakeApi.onGet('/incident-types', () => {
        'data': [
          {'slug': 'inondation', 'label_fr': 'Inondation'},
          {'slug': 'vol', 'label_fr': 'Vol'},
        ],
      });

      await provider.fetchIncidentTypes();

      expect(provider.incidentTypes, hasLength(2));
      expect(provider.incidentTypes.first.slug, 'inondation');
      expect(provider.labelForType('inondation'), 'Inondation');
    });

    test('falls back to hardcoded list when API is empty', () async {
      fakeApi.onGet('/incident-types', () => {'data': []});

      await provider.fetchIncidentTypes();

      expect(provider.incidentTypes, isNotEmpty);
      expect(provider.labelForType('agression'), 'Agression');
      expect(provider.labelForType('sos'), 'Alerte SOS');
    });

    test('falls back to cache then hardcoded when API fails', () async {
      await fakeDb.put('incident_types', [
        {'slug': 'braquage', 'label_fr': 'Braquage'},
      ]);

      await provider.fetchIncidentTypes();

      expect(provider.labelForType('braquage'), 'Braquage');
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
