import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safealert/providers/contacts_provider.dart';
import '../mocks.dart';

void main() {
  late FakeApiService fakeApi;
  late FakeLocalDatabase fakeDb;
  late ContactsProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeApi = FakeApiService();
    fakeDb = FakeLocalDatabase();
    provider = ContactsProvider(apiService: fakeApi, localDatabase: fakeDb);
  });

  group('fetchContacts', () {
    test('fetches contacts from API', () async {
      fakeApi.onGet('/contacts', () => {
        'data': [
          {'id': 'c1', 'contact_name': 'Marie', 'contact_phone': '+24381111111'},
        ],
      });

      await provider.fetchContacts();

      expect(provider.contacts.length, 1);
      expect(provider.contacts[0]['contact_name'], 'Marie');
      expect(provider.loading, false);
      expect(provider.isOffline, false);
    });

    test('maps status field to is_online', () async {
      fakeApi.onGet('/contacts', () => {
        'data': [
          {'id': 'c1', 'contact_name': 'Marie', 'status': 'online'},
          {'id': 'c2', 'contact_name': 'Paul', 'status': 'offline'},
        ],
      });

      await provider.fetchContacts();

      expect(provider.contacts[0]['is_online'], true);
      expect(provider.contacts[1]['is_online'], false);
    });

    test('falls back to cache on error', () async {
      await fakeDb.put('contacts', [
        {'id': 'c2', 'contact_name': 'Paul'},
      ]);

      await provider.fetchContacts();

      expect(provider.contacts.length, 1);
      expect(provider.contacts[0]['contact_name'], 'Paul');
      expect(provider.isOffline, true);
    });

    test('sets empty list when cache misses on error', () async {
      await provider.fetchContacts();

      expect(provider.contacts, isEmpty);
      expect(provider.isOffline, false);
    });
  });

  group('addContact', () {
    test('posts contact and refreshes list', () async {
      fakeApi.onPost('/contacts', () => {'id': 'c3'});
      fakeApi.onGet('/contacts', () => {'data': []});

      final result = await provider.addContact('Jean', '+24382222222');

      expect(result, true);
      expect(fakeApi.lastBody!['contact_name'], 'Jean');
      expect(fakeApi.lastBody!['contact_phone'], '+24382222222');
    });

    test('returns false on failure', () async {
      final result = await provider.addContact('Jean', '+24382222222');

      expect(result, false);
    });
  });

  group('deleteContact', () {
    test('deletes contact and refreshes', () async {
      fakeApi.onDelete('/contacts/c1', () => {'message': 'SupprimÃ©'});
      fakeApi.onGet('/contacts', () => {'data': []});

      final result = await provider.deleteContact('c1');

      expect(result, true);
    });

    test('returns false on failure', () async {
      final result = await provider.deleteContact('nonexistent');

      expect(result, false);
    });
  });

  group('clearCache', () {
    test('removes contacts from cache and clears list', () async {
      await fakeDb.put('contacts', [{'id': 'c1'}]);
      provider = ContactsProvider(apiService: fakeApi, localDatabase: fakeDb);

      await provider.clearCache();

      final cached = await fakeDb.get('contacts');
      expect(cached, isNull);
      expect(provider.contacts, isEmpty);
    });
  });
}
