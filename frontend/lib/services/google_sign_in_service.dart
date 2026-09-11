import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Web OAuth client (public) — same audience as backend `GOOGLE_CLIENT_ID`.
/// Prefer `--dart-define=GOOGLE_SERVER_CLIENT_ID=…`; default matches
/// `google-services.json` client_type 3 (be940).
const kGoogleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue:
      '552870535150-8i0ki30r45bipf8ren9ajtfp5bt5ipkr.apps.googleusercontent.com',
);

/// First 20 chars of the configured Web client (public) — safe to show in UI.
String get kGoogleServerClientIdPrefix {
  final id = kGoogleServerClientId.trim();
  if (id.isEmpty) return '(vide)';
  return id.length <= 20 ? id : id.substring(0, 20);
}

bool _blobLooksLikeError10(String blob) {
  final b = blob.toLowerCase();
  return b.contains('apiexception: 10') ||
      b.contains('api exception: 10') ||
      b.contains('developer_error') ||
      b.contains('developer console is not setup') ||
      RegExp(r'\b10:').hasMatch(b);
}

/// Maps native Google Sign-In failures to short French copy (no stacks).
/// Returns null when the user cancelled.
String? mapGoogleSignInError(Object error) {
  if (error is GoogleSignInException) {
    switch (error.code) {
      case GoogleSignInExceptionCode.canceled:
      case GoogleSignInExceptionCode.interrupted:
        return null;
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Erreur Google config (v7). Web=$kGoogleServerClientIdPrefix… '
            'Complétez Branding OAuth et republiez Audience, '
            'ou recréez les clients Android be940.';
      default:
        final desc = '${error.description ?? ''} ${error.toString()}';
        if (_blobLooksLikeError10(desc)) {
          return 'Erreur 10 (Credential Manager). Web=$kGoogleServerClientIdPrefix… '
              'Branding OAuth + Identity Toolkit + clients Android be940.';
        }
        return 'Connexion Google impossible. Réessayez.';
    }
  }
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    final blob = '${error.message ?? ''} ${error.details ?? ''}'.toLowerCase();
    if (code.contains('cancel') || blob.contains('12501') || blob.contains('sign_in_canceled')) {
      return null;
    }
    if (_blobLooksLikeError10(blob) || code == '10') {
      return 'Erreur 10. Web=$kGoogleServerClientIdPrefix… '
          'SHA Play OK — complétez Branding et Publish Audience (be940).';
    }
    if (blob.contains('apiexception: 7') || blob.contains('network') || code == '7') {
      return 'Réseau indisponible. Vérifiez votre connexion.';
    }
    if (blob.contains('id_token') || blob.contains('idtoken') || code == 'id_token_missing') {
      return 'Connexion Google mal configurée (jeton manquant). '
          'Web=$kGoogleServerClientIdPrefix…';
    }
    return 'Connexion Google impossible. Réessayez.';
  }
  final text = error.toString().toLowerCase();
  if (text.contains('cancel')) return null;
  if (_blobLooksLikeError10(text)) {
    return 'Erreur 10. Web=$kGoogleServerClientIdPrefix… '
        'Complétez Branding OAuth (be940) puis Publish Audience.';
  }
  return 'Connexion Google impossible. Réessayez.';
}

class GoogleSignInService {
  GoogleSignInService();

  bool _ready = false;

  Future<void> _ensureInitialized() async {
    if (_ready) return;
    await GoogleSignIn.instance.initialize(
      serverClientId:
          kGoogleServerClientId.isEmpty ? null : kGoogleServerClientId,
    );
    _ready = true;
    debugPrint(
      'GoogleSignIn v7 init Web=$kGoogleServerClientIdPrefix… '
      '(len=${kGoogleServerClientId.length})',
    );
  }

  /// Returns the Google ID token, or null if the user cancelled.
  Future<String?> signInIdToken() async {
    await _ensureInitialized();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      /* ignore — force a fresh account picker */
    }
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw PlatformException(
          code: 'id_token_missing',
          message: 'id_token_missing',
        );
      }
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      rethrow;
    }
  }
}
