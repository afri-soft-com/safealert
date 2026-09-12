import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:safealert/services/google_sign_in_service.dart';

void main() {
  test('canceled still shows diagnostic (Credential Manager disguise)', () {
    final msg = mapGoogleSignInError(GoogleSignInException(
      code: GoogleSignInExceptionCode.canceled,
      description: 'User canceled',
    ));
    expect(msg, isNotNull);
    expect(msg, contains('fermée sans compte'));
    expect(msg, contains('Web=$kGoogleServerClientIdPrefix'));
    expect(msg, contains('canceled'));
  });

  test('ApiException 10 PlatformException maps with Web prefix', () {
    final msg = mapGoogleSignInError(PlatformException(
      code: 'sign_in_failed',
      message: 'com.google.android.gms.common.api.ApiException: 10:',
    ));
    expect(msg, contains('Erreur 10'));
    expect(msg, contains('Web=$kGoogleServerClientIdPrefix'));
    expect(kGoogleServerClientIdPrefix, startsWith('552870535150-8i0ki'));
  });

  test('providerConfigurationError maps to config message', () {
    final msg = mapGoogleSignInError(GoogleSignInException(
      code: GoogleSignInExceptionCode.providerConfigurationError,
      description: 'provider issue',
    ));
    expect(msg, contains('config'));
    expect(msg, contains('provider issue'));
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
