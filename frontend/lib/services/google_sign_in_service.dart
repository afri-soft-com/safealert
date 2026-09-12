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

String _exDetail(GoogleSignInException e) {
  final parts = <String>[
    e.code.name,
    if (e.description != null && e.description!.trim().isNotEmpty) e.description!.trim(),
    if (e.details != null) e.details.toString(),
  ];
  return parts.join(' | ');
}

/// Maps native Google Sign-In failures to short French copy (no stacks).
///
/// Never returns null for a real failure — Credential Manager often reports
/// OAuth/SHA misconfig as [GoogleSignInExceptionCode.canceled], which must
/// still show a message so the user is not left with a silent no-op.
String? mapGoogleSignInError(Object error) {
  if (error is GoogleSignInException) {
    final detail = _exDetail(error);
    switch (error.code) {
      case GoogleSignInExceptionCode.canceled:
      case GoogleSignInExceptionCode.interrupted:
        // Often a disguised DEVELOPER_ERROR / NoCredential on Android CM.
        return 'Connexion Google fermée sans compte. '
            'Si vous n’avez pas annulé : config OAuth/SHA. '
            'Web=$kGoogleServerClientIdPrefix… ($detail)';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Erreur Google config. Web=$kGoogleServerClientIdPrefix… ($detail)';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'Google Sign-In indisponible (pas d’Activity). Réessayez.';
      case GoogleSignInExceptionCode.userMismatch:
        return 'Compte Google différent de la session en cours. Réessayez.';
      case GoogleSignInExceptionCode.unknownError:
        if (_blobLooksLikeError10(detail)) {
          return 'Erreur 10 (Credential Manager). '
              'Web=$kGoogleServerClientIdPrefix… ($detail)';
        }
        return 'Connexion Google impossible. Web=$kGoogleServerClientIdPrefix… ($detail)';
    }
  }
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    final blob = '${error.message ?? ''} ${error.details ?? ''}'.toLowerCase();
    if (code == 'google_dismissed' ||
        code.contains('cancel') ||
        blob.contains('12501') ||
        blob.contains('sign_in_canceled')) {
      return 'Connexion Google fermée sans compte. '
          'Si vous n’avez pas annulé : config OAuth/SHA. '
          'Web=$kGoogleServerClientIdPrefix…';
    }
    if (_blobLooksLikeError10(blob) || code == '10') {
      return 'Erreur 10. Web=$kGoogleServerClientIdPrefix…';
    }
    if (blob.contains('apiexception: 7') || blob.contains('network') || code == '7') {
      return 'Réseau indisponible. Vérifiez votre connexion.';
    }
    if (blob.contains('id_token') || blob.contains('idtoken') || code == 'id_token_missing') {
      return 'Connexion Google mal configurée (jeton manquant). '
          'Web=$kGoogleServerClientIdPrefix…';
    }
    return 'Connexion Google impossible (${error.code}). '
        'Web=$kGoogleServerClientIdPrefix…';
  }
  final text = error.toString();
  if (text.toLowerCase().contains('cancel')) {
    return 'Connexion Google fermée sans compte. '
        'Si vous n’avez pas annulé : config OAuth/SHA. '
        'Web=$kGoogleServerClientIdPrefix…';
  }
  if (_blobLooksLikeError10(text)) {
    return 'Erreur 10. Web=$kGoogleServerClientIdPrefix…';
  }
  return 'Connexion Google impossible. Web=$kGoogleServerClientIdPrefix… ($text)';
}

class GoogleSignInService {
  GoogleSignInService();

  bool _ready = false;

  Future<void> _ensureInitialized() async {
    if (_ready) return;
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw PlatformException(
        code: 'google_unsupported',
        message: 'authenticate_unsupported',
      );
    }
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

  /// Returns the Google ID token, or null only for a true empty success path
  /// (should not happen with [authenticate]). Failures throw / map to UI text.
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
      // Never swallow — Credential Manager maps many config failures to canceled.
      debugPrint('GoogleSignInException ${_exDetail(e)}');
      rethrow;
    }
  }
}
