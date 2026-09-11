import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safealert/services/google_sign_in_service.dart';

void main() {
  test('ApiException 10 maps to diagnostic with Web client prefix', () {
    final msg = mapGoogleSignInError(PlatformException(
      code: 'sign_in_failed',
      message: 'com.google.android.gms.common.api.ApiException: 10:',
    ));
    expect(msg, contains('erreur 10'));
    expect(msg, contains('Web=$kGoogleServerClientIdPrefix'));
    expect(msg, contains('Audience'));
    expect(kGoogleServerClientIdPrefix.length, lessThanOrEqualTo(20));
    expect(kGoogleServerClientIdPrefix, startsWith('552870535150-8i0ki'));
  });

  test('cancelled sign-in maps to null', () {
    expect(
      mapGoogleSignInError(PlatformException(code: 'sign_in_canceled', message: '12501')),
      isNull,
    );
  });

  test('missing id token maps to config message with Web prefix', () {
    final msg = mapGoogleSignInError(PlatformException(
      code: 'id_token_missing',
      message: 'id_token_missing',
    ));
    expect(msg, contains('jeton manquant'));
    expect(msg, contains('Web=$kGoogleServerClientIdPrefix'));
  });
}
