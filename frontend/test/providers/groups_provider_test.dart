import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safealert/providers/groups_provider.dart';
import '../mocks.dart';

void main() {
  late FakeApiService fakeApi;
  late FakeLocalDatabase fakeDb;
  late GroupsProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeApi = FakeApiService();
    fakeDb = FakeLocalDatabase();
    provider = GroupsProvider(apiService: fakeApi, localDatabase: fakeDb);
  });

  group('fetchMyGroups', () {
    test('fetches groups from API', () async {
      fakeApi.onGet('/groups', () => {
        'data': [
          {'id': 'g1', 'name': 'Voisins Kintambo', 'member_count': 12},
        ],
      });

      await provider.fetchMyGroups();

      expect(provider.myGroups.length, 1);
      expect(provider.myGroups[0]['name'], 'Voisins Kintambo');
      expect(provider.loading, false);
      expect(provider.isOffline, false);
    });

    test('falls back to cache on error', () async {
      await fakeDb.put('my_groups', [
        {'id': 'g2', 'name': 'SÃ©curitÃ© Gombe'},
      ]);

      await provider.fetchMyGroups();

      expect(provider.myGroups.length, 1);
      expect(provider.myGroups[0]['name'], 'SÃ©curitÃ© Gombe');
      expect(provider.isOffline, true);
    });

    test('sets empty list when cache misses on error', () async {
      await provider.fetchMyGroups();

      expect(provider.myGroups, isEmpty);
      expect(provider.isOffline, false);
    });
  });

  group('fetchDiscoverable', () {
    test('fetches discoverable groups', () async {
      fakeApi.onGet('/groups/discover', () => {
        'data': [
          {'id': 'g3', 'name': 'Quartier Libre', 'member_count': 5},
        ],
      });

      await provider.fetchDiscoverable();

      expect(provider.discoverable.length, 1);
      expect(provider.discoverable[0]['name'], 'Quartier Libre');
    });

    test('falls back to cache on error', () async {
      await fakeDb.put('discover_groups', [
        {'id': 'g4', 'name': 'Groupe CachÃ©'},
      ]);

      await provider.fetchDiscoverable();

      expect(provider.discoverable.length, 1);
      expect(provider.discoverable[0]['name'], 'Groupe CachÃ©');
    });
  });

  group('createGroup', () {
    test('creates group and refreshes my groups', () async {
      fakeApi.onPost('/groups', () => {'id': 'g5', 'name': 'Nouveau Groupe'});
      fakeApi.onGet('/groups', () => {'data': []});

      final result = await provider.createGroup('Nouveau Groupe');

      expect(result, true);
      expect(fakeApi.lastBody!['name'], 'Nouveau Groupe');
    });

    test('sends optional fields', () async {
      fakeApi.onPost('/groups', () => {'id': 'g6'});
      fakeApi.onGet('/groups', () => {'data': []});

      await provider.createGroup('Test', description: 'Desc', zoneName: 'Zone');

      expect(fakeApi.lastBody!['description'], 'Desc');
      expect(fakeApi.lastBody!['zone_name'], 'Zone');
    });

    test('returns false on failure', () async {
      final result = await provider.createGroup('Fail');

      expect(result, false);
    });
  });

  group('joinGroup', () {
    test('sends join request and refreshes discoverable', () async {
      fakeApi.onPost('/groups/join', () => {'message': 'Demande envoyée', 'status': 'pending'});
      fakeApi.onGet('/groups/discover', () => {'data': []});

      final result = await provider.joinGroup('ABCD12');

      expect(result, true);
      expect(fakeApi.lastBody!['invite_code'], 'ABCD12');
      expect(provider.lastJoinMessage, 'Demande envoyée');
    });

    test('returns false on failure', () async {
      final result = await provider.joinGroup('INVALID');

      expect(result, false);
    });
  });

  group('join requests admin', () {
    test('fetches join requests for group', () async {
      fakeApi.onGet('/groups/g1/join-requests', () => {
        'data': [
          {'id': 'r1', 'pseudo': 'Marie', 'phone': '+243812345678'},
        ],
      });

      await provider.fetchJoinRequests('g1');

      expect(provider.joinRequestsFor('g1').length, 1);
      expect(provider.joinRequestsFor('g1')[0]['pseudo'], 'Marie');
    });

    test('approves join request', () async {
      fakeApi.onPut('/groups/join-requests/r1/approve', () => {'status': 'approved'});
      fakeApi.onGet('/groups/g1/join-requests', () => {'data': []});
      fakeApi.onGet('/groups', () => {'data': []});

      final result = await provider.approveJoinRequest('r1', 'g1');

      expect(result, true);
    });
  });

  group('leaveGroup', () {
    test('leaves group and refreshes my groups', () async {
      fakeApi.onDelete('/groups/g1/leave', () => {'message': 'QuittÃ©'});
      fakeApi.onGet('/groups', () => {'data': []});

      final result = await provider.leaveGroup('g1');

      expect(result, true);
    });

    test('returns false on failure', () async {
      final result = await provider.leaveGroup('g999');

      expect(result, false);
    });
  });
}
