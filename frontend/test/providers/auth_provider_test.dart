import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safealert/providers/auth_provider.dart';
import '../mocks.dart';
import 'package:safealert/services/api_service.dart';

void main() {
  late FakeApiService fakeApi;
  late AuthProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeApi = FakeApiService();
    provider = AuthProvider(apiService: fakeApi);
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
      final result = await provider.requestCode('+243811234567');

      expect(result, false);
      expect(provider.error, contains('réseau'));
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
      provider = AuthProvider(apiService: fakeApi);
      provider.logout();

      expect(fakeApi.hasToken, false);
      expect(provider.isAuthenticated, false);
      expect(provider.user, isNull);
      expect(provider.phone, isNull);
    });
  });
}
