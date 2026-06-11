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

    test('sets empty list when cache misses on error', () async {
      await provider.fetchNumbers();

      expect(provider.numbers, isEmpty);
      expect(provider.isOffline, false);
    });
  });
}
