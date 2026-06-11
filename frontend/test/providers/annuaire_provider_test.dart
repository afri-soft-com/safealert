import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safealert/providers/annuaire_provider.dart';
import '../mocks.dart';

void main() {
  late FakeApiService fakeApi;
  late FakeLocalDatabase fakeDb;
  late AnnuaireProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeApi = FakeApiService();
    fakeDb = FakeLocalDatabase();
    provider = AnnuaireProvider(apiService: fakeApi, localDatabase: fakeDb);
  });

  group('fetchNumbers', () {
    test('fetches numbers from API', () async {
      fakeApi.onGet('/annuaire', () => {
        'data': [
          {'id': 1, 'service_name': 'Police', 'phone_number': '112', 'service_type': 'police'},
        ],
      });

      await provider.fetchNumbers();

      expect(provider.numbers.length, 1);
      expect(provider.numbers[0]['service_name'], 'Police');
      expect(provider.loading, false);
      expect(provider.isOffline, false);
    });

    test('applies country filter', () async {
      fakeApi.onGet('/annuaire?country=cd', () => {'data': []});

      await provider.fetchNumbers(country: 'cd');

      expect(fakeApi.lastPath, '/annuaire?country=cd');
    });

    test('falls back to cache on error', () async {
      await fakeDb.put('annuaire', [
        {'id': 2, 'service_name': 'Ambulance'},
      ]);

      await provider.fetchNumbers();

      expect(provider.numbers.length, 1);
      expect(provider.numbers[0]['service_name'], 'Ambulance');
      expect(provider.isOffline, true);
    });

    test('caches numbers after successful fetch', () async {
      fakeApi.onGet('/annuaire', () => {
        'data': [
          {'id': 3, 'service_name': 'Pompiers', 'phone_number': '118'},
        ],
      });

      await provider.fetchNumbers();

      final cached = await fakeDb.get('annuaire', maxAgeSeconds: 86400);
      expect(cached, isNotNull);
      expect((cached as List).first['service_name'], 'Pompiers');
    });

    test('preloads cache before API response', () async {
      await fakeDb.put('annuaire', [
        {'id': 4, 'service_name': 'Police'},
      ]);
      fakeApi.onGet('/annuaire', () => {
        'data': [
          {'id': 5, 'service_name': 'Police nationale'},
        ],
      });

      await provider.fetchNumbers();

      expect(provider.numbers.first['service_name'], 'Police nationale');
      expect(provider.isOffline, false);
    });

    test('uses country-specific cache key', () async {
      await fakeDb.put('annuaire_cd', [
        {'id': 6, 'service_name': 'Urgences CD'},
      ]);

      await provider.fetchNumbers(country: 'cd');

      expect(provider.numbers.first['service_name'], 'Urgences CD');
      expect(provider.isOffline, true);
    });

    test('sets empty list when cache misses on error', () async {
      await provider.fetchNumbers();

      expect(provider.numbers, isEmpty);
      expect(provider.isOffline, false);
    });
  });
}
