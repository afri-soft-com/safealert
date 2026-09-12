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
/// Returns null only for a genuine user cancel (12501 / sign_in_canceled).
String? mapGoogleSignInError(Object error) {
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    final blob = '${error.message ?? ''} ${error.details ?? ''}'.toLowerCase();
    if (code.contains('cancel') ||
        blob.contains('12501') ||
        blob.contains('sign_in_canceled')) {
      // Legacy Google Sign-In: real cancel. Still hint if it looks like error 10.
      if (_blobLooksLikeError10(blob)) {
        return 'Erreur 10 (masquée en annulation). '
            'Web=$kGoogleServerClientIdPrefix… Recréez les clients Android be940.';
      }
      return 'Connexion Google fermée sans compte. '
          'Si vous n’avez pas annulé : OAuth/SHA. '
          'Web=$kGoogleServerClientIdPrefix…';
    }
    if (_blobLooksLikeError10(blob) || code == '10') {
      return 'Erreur 10 (package/SHA). Web=$kGoogleServerClientIdPrefix… '
          'Clients Android be940 doivent avoir SHA Play classique + PQC + upload.';
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
  final lower = text.toLowerCase();
  if (lower.contains('cancel') || lower.contains('12501')) {
    return 'Connexion Google fermée sans compte. '
        'Si vous n’avez pas annulé : OAuth/SHA. '
        'Web=$kGoogleServerClientIdPrefix…';
  }
  if (_blobLooksLikeError10(text)) {
    return 'Erreur 10 (package/SHA). Web=$kGoogleServerClientIdPrefix…';
  }
  return 'Connexion Google impossible. Web=$kGoogleServerClientIdPrefix…';
}

class GoogleSignInService {
  GoogleSignInService({GoogleSignIn? client}) : _client = client;

  final GoogleSignIn? _client;
  GoogleSignIn? _defaultClient;

  /// google_sign_in 6.x — same pattern as working SENGA/Mova.
  /// Credential Manager (v7) was reporting OAuth failures as "canceled".
  GoogleSignIn get _google {
    final injected = _client;
    if (injected != null) return injected;
    return _defaultClient ??= GoogleSignIn(
      serverClientId:
          kGoogleServerClientId.isEmpty ? null : kGoogleServerClientId,
    );
  }

  /// Returns the Google ID token, or null if the user cancelled.
  Future<String?> signInIdToken() async {
    debugPrint(
      'GoogleSignIn v6 serverClientId=$kGoogleServerClientIdPrefix… '
      '(len=${kGoogleServerClientId.length})',
    );
    try {
      await _google.signOut();
    } catch (_) {
      /* ignore — force a fresh account picker */
    }
    final account = await _google.signIn();
    if (account == null) return null;
    var auth = await account.authentication;
    var token = auth.idToken;
    if (token == null || token.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      auth = await account.authentication;
      token = auth.idToken;
    }
    if (token == null || token.isEmpty) {
      throw PlatformException(
        code: 'id_token_missing',
        message: 'id_token_missing',
      );
    }
    return token;
  }
}
