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

  test('clampMinute snaps to 0/15/30/45', () {
    expect(NeighborhoodProvider.clampMinute(0), 0);
    expect(NeighborhoodProvider.clampMinute(30), 30);
    expect(NeighborhoodProvider.clampMinute(20), 15);
    expect(NeighborhoodProvider.clampMinute(44), 30);
    expect(NeighborhoodProvider.clampMinute(50), 45);
  });

  test('subscribe sends GPS + city + radius', () async {
    fakeApi.onPost('/neighborhood/subscribe', () => {
      'id': 's1',
      'quartier': 'Gombe',
      'city': 'Kinshasa',
      'digest_hour': 9,
      'digest_minute': 30,
      'lat': -4.3,
      'lng': 15.3,
      'radius_m': 5000,
    });
    fakeApi.onGet('/neighborhood', () => {
      'data': [
        {
          'id': 's1',
          'quartier': 'Gombe',
          'city': 'Kinshasa',
          'digest_hour': 9,
          'digest_minute': 30,
        },
      ],
    });

    await provider.subscribe(
      quartier: 'Gombe',
      digestHour: 9,
      digestMinute: 30,
      city: 'Kinshasa',
      lat: -4.3,
      lng: 15.3,
      radiusM: 5000,
    );

    expect(fakeApi.lastBody!['quartier'], 'Gombe');
    expect(fakeApi.lastBody!['city'], 'Kinshasa');
    expect(fakeApi.lastBody!['lat'], -4.3);
    expect(fakeApi.lastBody!['lng'], 15.3);
    expect(fakeApi.lastBody!['radius_m'], 5000);
    expect(fakeApi.lastBody!['digest_minute'], anyOf(0, 15, 30, 45));
    expect(provider.subscriptions, hasLength(1));
  });

  test('updateTime PATCHes hour+minute then reloads', () async {
    fakeApi.onPatch('/neighborhood/s1', () => {
      'id': 's1',
      'quartier': 'Gombe',
      'digest_hour': 7,
      'digest_minute': 15,
    });
    fakeApi.onGet('/neighborhood', () => {
      'data': [
        {'id': 's1', 'quartier': 'Gombe', 'digest_hour': 7, 'digest_minute': 15},
      ],
    });

    await provider.updateTime('s1', 7, 15);

    expect(fakeApi.lastBody!['digest_hour'], isA<int>());
    expect(fakeApi.lastBody!['digest_minute'], anyOf(0, 15, 30, 45));
    expect(provider.subscriptions.first['digest_minute'], 15);
  });

  test('sendNow posts to send-now', () async {
    fakeApi.onPost('/neighborhood/s1/send-now', () => {
      'message': 'Résumé envoyé',
      'total': 1,
      'sos': 0,
    });
    await provider.sendNow('s1');
    expect(fakeApi.lastPath, '/neighborhood/s1/send-now');
  });

  test('nextLocalSlot returns a valid slot', () {
    final slot = NeighborhoodProvider.nextLocalSlot(minAhead: 5);
    expect(slot.hour, inInclusiveRange(0, 23));
    expect(NeighborhoodProvider.digestMinuteSlots, contains(slot.minute));
  });
}
