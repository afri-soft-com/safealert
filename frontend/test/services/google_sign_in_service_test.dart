import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:safealert/services/google_sign_in_service.dart';

void main() {
  test('ApiException 10 maps to Branding diagnostic with Web prefix', () {
    final msg = mapGoogleSignInError(PlatformException(
      code: 'sign_in_failed',
      message: 'com.google.android.gms.common.api.ApiException: 10:',
    ));
    expect(msg, contains('Erreur 10'));
    expect(msg, contains('Web=$kGoogleServerClientIdPrefix'));
    expect(msg, contains('Branding'));
    expect(kGoogleServerClientIdPrefix.length, lessThanOrEqualTo(20));
    expect(kGoogleServerClientIdPrefix, startsWith('552870535150-8i0ki'));
  });

  test('GoogleSignInException clientConfigurationError maps to config message', () {
    final msg = mapGoogleSignInError(GoogleSignInException(
      code: GoogleSignInExceptionCode.clientConfigurationError,
      description: 'bad config',
    ));
    expect(msg, contains('config'));
    expect(msg, contains('Web=$kGoogleServerClientIdPrefix'));
  });

  test('GoogleSignInException canceled maps to null', () {
    expect(
      mapGoogleSignInError(GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      )),
      isNull,
    );
  });

  test('cancelled PlatformException maps to null', () {
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
