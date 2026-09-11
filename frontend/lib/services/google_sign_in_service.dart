import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Web client ID (public) passed at build time — same as backend GOOGLE_CLIENT_ID.
const kGoogleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

/// Maps native Google Sign-In failures to short French copy (no stacks).
/// Returns null when the user cancelled.
String? mapGoogleSignInError(Object error) {
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    final blob = '${error.message ?? ''} ${error.details ?? ''}'.toLowerCase();
    if (code.contains('cancel') || blob.contains('12501') || blob.contains('sign_in_canceled')) {
      return null;
    }
    if (blob.contains('apiexception: 10') ||
        blob.contains('api exception: 10') ||
        blob.contains('developer_error') ||
        RegExp(r'\b10:').hasMatch(blob) ||
        code == '10') {
      return 'Connexion Google refusée (erreur 10). Empreintes SHA-1 Firebase : Play App Signing et clé d’upload (même package).';
    }
    if (blob.contains('apiexception: 7') || blob.contains('network') || code == '7') {
      return 'Réseau indisponible. Vérifiez votre connexion.';
    }
    if (blob.contains('id_token') || blob.contains('idtoken')) {
      return 'Connexion Google mal configurée (jeton manquant). Vérifiez l’identifiant client Web.';
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
  GoogleSignIn? _defaultClient;

  /// google_sign_in 6.x: constructor `serverClientId` (not v7 `initialize()`).
  GoogleSignIn get _google {
    final injected = _client;
    if (injected != null) return injected;
    return _defaultClient ??= GoogleSignIn(
      serverClientId: kGoogleServerClientId.isEmpty ? null : kGoogleServerClientId,
      scopes: const ['email', 'profile'],
    );
  }

  /// Returns the Google ID token, or null if the user cancelled.
  Future<String?> signInIdToken() async {
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
