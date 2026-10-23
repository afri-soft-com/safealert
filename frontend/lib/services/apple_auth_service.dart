import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Sign in with Apple — required on iOS when Google is offered (App Store 4.8).
class AppleAuthService {
  static bool get isAvailable {
    if (kIsWeb) return false;
    return Platform.isIOS;
  }

  /// Returns identityToken + name (name only on first Apple authorization).
  static Future<({String identityToken, String? fullName})?> obtainCredentials() async {
    if (!isAvailable) return null;
    final available = await SignInWithApple.isAvailable();
    if (!available) return null;

    final cred = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    final token = cred.identityToken;
    if (token == null || token.isEmpty) return null;

    final parts = [
      if (cred.givenName != null && cred.givenName!.trim().isNotEmpty) cred.givenName!.trim(),
      if (cred.familyName != null && cred.familyName!.trim().isNotEmpty) cred.familyName!.trim(),
    ];
    final fullName = parts.isEmpty ? null : parts.join(' ');
    return (identityToken: token, fullName: fullName);
  }

  static String errorMessage(Object e) {
    if (e is SignInWithAppleAuthorizationException) {
      switch (e.code) {
        case AuthorizationErrorCode.canceled:
          return 'Connexion Apple annulée';
        case AuthorizationErrorCode.notHandled:
        case AuthorizationErrorCode.notInteractive:
          return 'Connexion Apple indisponible sur cet appareil';
        default:
          return 'Échec connexion Apple (${e.code.name})';
      }
    }
    final s = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    return s;
  }
}
