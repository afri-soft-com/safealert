import 'package:flutter_test/flutter_test.dart';
import 'package:safealert/providers/neighborhood_provider.dart';
import '../mocks.dart';

void main() {
  late FakeApiService fakeApi;
  late NeighborhoodProvider provider;

  setUp(() {
    fakeApi = FakeApiService();
    provider = NeighborhoodProvider(apiService: fakeApi);
  });

  test('clampHour keeps 0 and 23', () {
    expect(NeighborhoodProvider.clampHour(0), 0);
    expect(NeighborhoodProvider.clampHour(23), 23);
    expect(NeighborhoodProvider.clampHour(-2), 0);
    expect(NeighborhoodProvider.clampHour(30), 23);
  });

  test('subscribe sends chosen digest_hour', () async {
    fakeApi.onPost('/neighborhood/subscribe', () => {
      'id': 's1',
      'quartier': 'Gombe',
      'digest_hour': 9,
    });
    fakeApi.onGet('/neighborhood', () => {
      'data': [
        {'id': 's1', 'quartier': 'Gombe', 'digest_hour': 9},
      ],
    });

    await provider.subscribe('Gombe', 9);

    expect(fakeApi.lastPath, '/neighborhood');
    expect(fakeApi.lastBody!['quartier'], 'Gombe');
    expect(fakeApi.lastBody!['digest_hour'], 9);
    expect(provider.subscriptions, hasLength(1));
    expect(provider.subscriptions.first['digest_hour'], 9);
  });

  test('subscribe sends midnight hour 0 (not 18)', () async {
    fakeApi.onPost('/neighborhood/subscribe', () => {
      'id': 's0',
      'quartier': 'Limete',
      'digest_hour': 0,
    });
    fakeApi.onGet('/neighborhood', () => {
      'data': [
        {'id': 's0', 'quartier': 'Limete', 'digest_hour': 0},
      ],
    });

    await provider.subscribe('Limete', 0);

    expect(fakeApi.lastBody!['digest_hour'], 0);
    expect(provider.subscriptions.first['digest_hour'], 0);
  });

  test('updateHour PATCHes digest_hour then reloads', () async {
    fakeApi.onPatch('/neighborhood/s1', () => {
      'id': 's1',
      'quartier': 'Gombe',
      'digest_hour': 7,
    });
    fakeApi.onGet('/neighborhood', () => {
      'data': [
        {'id': 's1', 'quartier': 'Gombe', 'digest_hour': 7},
      ],
    });

    await provider.updateHour('s1', 7);

    expect(fakeApi.lastPath, '/neighborhood');
    expect(fakeApi.lastBody!['digest_hour'], 7);
    expect(provider.subscriptions.first['digest_hour'], 7);
  });
}
