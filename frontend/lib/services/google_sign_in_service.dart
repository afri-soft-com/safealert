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

bool _isDeveloperError10(PlatformException error) {
  final code = error.code.toLowerCase();
  final blob = '${error.message ?? ''} ${error.details ?? ''}'.toLowerCase();
  return blob.contains('apiexception: 10') ||
      blob.contains('api exception: 10') ||
      blob.contains('developer_error') ||
      RegExp(r'\b10:').hasMatch(blob) ||
      code == '10' ||
      code == 'sha_ko';
}

/// Maps native Google Sign-In failures to short French copy (no stacks).
/// Returns null when the user cancelled.
String? mapGoogleSignInError(Object error) {
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    final blob = '${error.message ?? ''} ${error.details ?? ''}'.toLowerCase();
    if (code.contains('cancel') || blob.contains('12501') || blob.contains('sign_in_canceled')) {
      return null;
    }
    if (code == 'sha_ok_web_ko') {
      return 'Erreur 10 diagnostic: SHA Android OK, client Web refusé. '
          'Web=$kGoogleServerClientIdPrefix… '
          'Activez Identity Toolkit / republiez le consentement OAuth.';
    }
    if (code == 'sha_ko' || _isDeveloperError10(error)) {
      return 'Erreur 10 diagnostic: package+SHA refusés. '
          'Web=$kGoogleServerClientIdPrefix… '
          'Un autre projet Cloud a peut-être encore ce SHA. '
          'Vérifiez Clients Android be940 + projets 5082114/Kongomarket.';
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
  return 'Connexion Google impossible. Réessayez.';
}

class GoogleSignInService {
  GoogleSignInService({GoogleSignIn? client}) : _client = client;

  final GoogleSignIn? _client;

  GoogleSignIn _clientWithWeb() => GoogleSignIn(
        serverClientId: kGoogleServerClientId.isEmpty ? null : kGoogleServerClientId,
      );

  /// No serverClientId — tests whether Play Services accepts package+SHA alone.
  GoogleSignIn _clientShaOnly() => GoogleSignIn();

  Future<void> _freshSignOut(GoogleSignIn client) async {
    try {
      await client.signOut();
    } catch (_) {
      /* ignore */
    }
  }

  Future<String?> _idTokenFrom(GoogleSignIn client) async {
    await _freshSignOut(client);
    final account = await client.signIn();
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

  /// Returns the Google ID token, or null if the user cancelled.
  ///
  /// On ApiException 10 with Web `serverClientId`, retries without it to tell
  /// apart SHA/package rejection vs Web-client rejection.
  Future<String?> signInIdToken() async {
    debugPrint(
      'GoogleSignIn serverClientId prefix=$kGoogleServerClientIdPrefix… '
      '(len=${kGoogleServerClientId.length})',
    );
    final injected = _client;
    if (injected != null) {
      return _idTokenFrom(injected);
    }

    try {
      return await _idTokenFrom(_clientWithWeb());
    } on PlatformException catch (e) {
      if (!_isDeveloperError10(e)) rethrow;
      debugPrint('GoogleSignIn error 10 with Web client — retry SHA-only');
      try {
        final bare = _clientShaOnly();
        await _freshSignOut(bare);
        final account = await bare.signIn();
        if (account != null) {
          // Package+SHA accepted; Web serverClientId is the problem.
          throw PlatformException(
            code: 'sha_ok_web_ko',
            message: 'sha_ok_web_ko',
          );
        }
        // User cancelled the retry — treat as cancel.
        return null;
      } on PlatformException catch (e2) {
        if (e2.code == 'sha_ok_web_ko') rethrow;
        if (_isDeveloperError10(e2)) {
          throw PlatformException(code: 'sha_ko', message: 'sha_ko');
        }
        rethrow;
      }
    }
  }
}
