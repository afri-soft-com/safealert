import 'package:flutter_test/flutter_test.dart';
import 'package:safealert/services/local_pin_service.dart';

void main() {
  late MemoryPinStore store;
  late LocalPinService service;

  setUp(() {
    store = MemoryPinStore();
    service = LocalPinService(store: store);
  });

  test('hasPin is false until set', () async {
    expect(await service.hasPin(), false);
    expect(await service.storedPhone(), isNull);
  });

  test('setPin stores a hash, never the raw PIN', () async {
    await service.setPin('123456', phone: '+243811234567');

    expect(await service.hasPin(), true);
    expect(await service.storedPhone(), '+243811234567');
    expect(store.data[LocalPinService.hashKey], isNotNull);
    expect(store.data[LocalPinService.hashKey], isNot(contains('123456')));
    expect(store.data.values, isNot(contains('123456')));
    expect(store.data[LocalPinService.saltKey], isNotEmpty);
  });

  test('verify accepts the same PIN and rejects another', () async {
    await service.setPin('654321', phone: '+243811234567');

    expect(await service.verify('654321'), true);
    expect(await service.verify('000000'), false);
    expect(await service.verify('65432'), false);
  });

  test('rejects PIN shorter than 4 or longer than 6', () async {
    expect(
      () => service.setPin('123', phone: '+243811234567'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => service.setPin('1234567', phone: '+243811234567'),
      throwsA(isA<ArgumentError>()),
    );
    await service.setPin('1234', phone: '+243811234567');
    expect(await service.verify('1234'), true);
  });

  test('clear removes hash, salt and phone', () async {
    await service.setPin('111222', phone: '+243811234567');
    await service.clear();

    expect(await service.hasPin(), false);
    expect(await service.storedPhone(), isNull);
    expect(await service.verify('111222'), false);
    expect(store.data, isEmpty);
  });
}
