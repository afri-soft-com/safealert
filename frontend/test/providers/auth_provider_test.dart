import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safealert/providers/auth_provider.dart';
import 'package:safealert/services/local_pin_service.dart';
import '../mocks.dart';
import 'package:safealert/services/api_service.dart';

void main() {
  late FakeApiService fakeApi;
  late MemoryPinStore pinStore;
  late AuthProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeApi = FakeApiService();
    pinStore = MemoryPinStore();
    provider = AuthProvider(
      apiService: fakeApi,
      pinService: LocalPinService(store: pinStore),
    );
  });

  group('checkAuth', () {
    test('restores session when token exists', () async {
      await fakeApi.setToken('valid-token');
      fakeApi.onGet('/auth/profile', () => {'id': 'u1', 'phone': '+243811234567'});

      await provider.checkAuth();

      expect(provider.isAuthenticated, true);
      expect(provider.user, isNotNull);
      expect(provider.user!['id'], 'u1');
    });

    test('clears token when profile fetch fails', () async {
      await fakeApi.setToken('expired-token');

      await provider.checkAuth();

      expect(provider.isAuthenticated, false);
      expect(provider.user, isNull);
      expect(fakeApi.hasToken, false);
    });

    test('existing session without PIN requires setup', () async {
      await fakeApi.setToken('valid-token');
      fakeApi.onGet('/auth/profile', () => {'id': 'u1', 'phone': '+243811234567'});

      await provider.checkAuth();

      expect(provider.isAuthenticated, true);
      expect(provider.needsPinSetup, true);
      expect(provider.canEnterApp, false);
    });

    test('existing session with PIN stays gated until unlock', () async {
      final pins = LocalPinService(store: pinStore);
      await pins.setPin('123456', phone: '+243811234567');
      await fakeApi.setToken('valid-token');
      fakeApi.onGet('/auth/profile', () => {'id': 'u1', 'phone': '+243811234567'});

      await provider.checkAuth();

      expect(provider.isAuthenticated, true);
      expect(provider.hasLocalPin, true);
      expect(provider.needsPinUnlock, true);
      expect(provider.canEnterApp, false);
    });
  });

  group('requestCode', () {
    test('returns true on success', () async {
      fakeApi.onPost('/auth/request-code', () => {'message': 'Code envoyÃ©'});

      final result = await provider.requestCode('+243811234567');

      expect(result, true);
      expect(provider.phone, '+243811234567');
      expect(fakeApi.lastBody, {'phone': '+243811234567'});
    });

    test('returns false on ApiException', () async {
      fakeApi.onPost('/auth/request-code', () => throw ApiException('NumÃ©ro invalide', 400));

      final result = await provider.requestCode('+243811234567');

      expect(result, false);
      expect(provider.error, 'NumÃ©ro invalide');
    });

    test('returns false on network error', () async {
      fakeApi.onPost('/auth/request-code', () => throw const SocketException('Connection failed'));

      final result = await provider.requestCode('+243811234567');

      expect(result, false);
      expect(provider.error!.toLowerCase(), anyOf(contains('réseau'), contains('connexion')));
    });
  });

  group('verifyCode', () {
    test('returns false when phone is null', () async {
      final result = await provider.verifyCode('123456');

      expect(result, false);
    });

    test('verifies, sets token and returns true', () async {
    fakeApi.onPost('/auth/request-code', () => {'message': 'Code envoyÃ©'});
    fakeApi.onPost('/auth/verify-code', () => {
      'token': 'jwt-token',
      'user': {'id': 'u1', 'phone': '+243811234567', 'role': 'citizen'},
    });

    await provider.requestCode('+243811234567');
    final result = await provider.verifyCode('123456', pseudo: 'Test');

      expect(result, true);
      expect(provider.isAuthenticated, true);
      expect(provider.needsPinSetup, true);
      expect(provider.canEnterApp, false);
      expect(provider.user!['id'], 'u1');
      expect(fakeApi.token, 'jwt-token');
    });

    test('returns false on ApiException', () async {
      fakeApi.onPost('/auth/request-code', () => {'message': 'Code envoyÃ©'});
      fakeApi.onPost('/auth/verify-code', () => throw ApiException('Code invalide', 400));

      await provider.requestCode('+243811234567');
      final result = await provider.verifyCode('654321');

      expect(result, false);
      expect(provider.error, 'Code invalide');
    });
  });

  group('logout', () {
    test('clears auth state', () async {
      await fakeApi.setToken('some-token');
      provider = AuthProvider(
        apiService: fakeApi,
        pinService: LocalPinService(store: pinStore),
      );
      provider.logout();

      expect(fakeApi.hasToken, false);
      expect(provider.isAuthenticated, false);
      expect(provider.user, isNull);
      expect(provider.phone, isNull);
    });

    test('keeps local PIN for the same phone', () async {
      fakeApi.onPost('/auth/request-code', () => {'message': 'ok'});
      fakeApi.onPost('/auth/verify-code', () => {
        'token': 'jwt-token',
        'user': {'id': 'u1', 'phone': '+243811234567', 'role': 'citizen'},
      });
      await provider.requestCode('+243811234567');
      await provider.verifyCode('123456');
      await provider.setLocalPin('246810', confirm: '246810');

      await provider.logout();

      expect(provider.isAuthenticated, false);
      expect(provider.hasLocalPin, true);
      expect(provider.pinPhone, '+243811234567');
      expect(await LocalPinService(store: pinStore).verify('246810'), true);
    });
  });

  group('local PIN', () {
    Future<void> _otpLogin() async {
      fakeApi.onPost('/auth/request-code', () => {'message': 'ok'});
      fakeApi.onPost('/auth/verify-code', () => {
        'token': 'jwt-token',
        'user': {'id': 'u1', 'phone': '+243811234567', 'role': 'citizen'},
      });
      await provider.requestCode('+243811234567');
      await provider.verifyCode('123456');
    }

    test('set then unlock with valid session enters the app', () async {
      await _otpLogin();
      final saved = await provider.setLocalPin('135790', confirm: '135790');

      expect(saved, true);
      expect(provider.canEnterApp, true);
      expect(provider.needsPinSetup, false);

      provider = AuthProvider(
        apiService: fakeApi,
        pinService: LocalPinService(store: pinStore),
      );
      fakeApi.onGet('/auth/profile', () => {
        'id': 'u1',
        'phone': '+243811234567',
        'role': 'citizen',
      });
      await fakeApi.setToken('jwt-token');
      await provider.checkAuth();

      expect(provider.canEnterApp, false);
      expect(await provider.unlockWithPin('135790'), true);
      expect(provider.canEnterApp, true);
    });

    test('wrong PIN stays gated', () async {
      await _otpLogin();
      await provider.setLocalPin('135790', confirm: '135790');
      await provider.logout();
      await fakeApi.setToken('jwt-token');
      fakeApi.onGet('/auth/profile', () => {
        'id': 'u1',
        'phone': '+243811234567',
      });
      await provider.checkAuth();

      expect(await provider.unlockWithPin('000000'), false);
      expect(provider.error, 'Code PIN incorrect');
      expect(provider.canEnterApp, false);
    });

    test('correct PIN without session stays gated', () async {
      await _otpLogin();
      await provider.setLocalPin('135790', confirm: '135790');
      await provider.logout();

      expect(provider.hasLocalPin, true);
      expect(provider.isAuthenticated, false);
      expect(await provider.unlockWithPin('135790'), false);
      expect(provider.error, contains('Code PIN oublié'));
      expect(provider.canEnterApp, false);
    });

    test('mismatched confirmation is rejected', () async {
      await _otpLogin();
      final ok = await provider.setLocalPin('135790', confirm: '000000');

      expect(ok, false);
      expect(provider.error, 'Les codes PIN ne correspondent pas');
      expect(provider.needsPinSetup, true);
    });

    test('forgot PIN requests OTP to the stored phone', () async {
      await _otpLogin();
      await provider.setLocalPin('135790', confirm: '135790');
      await provider.logout();
      fakeApi.onPost('/auth/request-code', () => {'message': 'ok', 'devCode': '999111'});

      final ok = await provider.requestForgotPinCode();

      expect(ok, true);
      expect(fakeApi.lastBody, {'phone': '+243811234567'});
      expect(provider.phone, '+243811234567');
    });

    test('OTP on another phone resets the PIN', () async {
      await _otpLogin();
      await provider.setLocalPin('135790', confirm: '135790');
      fakeApi.onPost('/auth/request-code', () => {'message': 'ok'});
      fakeApi.onPost('/auth/verify-code', () => {
        'token': 'other-jwt',
        'user': {'id': 'u2', 'phone': '+243899999999', 'role': 'citizen'},
      });

      await provider.requestCode('+243899999999');
      await provider.verifyCode('123456');

      expect(provider.needsPinSetup, true);
      expect(provider.hasLocalPin, false);
      expect(await LocalPinService(store: pinStore).hasPin(), false);
    });
  });
}
