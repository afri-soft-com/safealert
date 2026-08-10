import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Exception API avec message déjà adapté à l'utilisateur quand possible.
class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);
  @override
  String toString() => message;
}

/// Message utilisateur pour les échecs HTTP non gérés par [ApiException].
String describeNetworkError(Object e) {
  if (e is TimeoutException) {
    return 'Délai dépassé — le serveur démarre peut-être. Attendez 30 s et réessayez.';
  }
  if (e is SocketException) {
    return 'Serveur inaccessible. Vérifiez votre connexion Internet.';
  }
  if (e is http.ClientException) {
    return 'Connexion interrompue. Vérifiez votre réseau.';
  }
  return 'Erreur réseau — vérifiez votre connexion.';
}

/// Codes HTTP → messages clairs (jamais de jargon technique en UI).
String messageForStatusCode(int statusCode) {
  switch (statusCode) {
    case 400:
      return 'Demande invalide. Vérifiez les informations saisies.';
    case 401:
      return 'Session expirée. Veuillez vous reconnecter.';
    case 403:
      return 'Accès non autorisé pour votre profil.';
    case 404:
      return 'Élément introuvable.';
    case 409:
      return 'Conflit : cette action n\'est plus possible.';
    case 422:
      return 'Informations incomplètes ou incorrectes.';
    case 429:
      return 'Trop de tentatives. Réessayez dans quelques instants.';
    case 500:
    case 502:
    case 503:
    case 504:
      return 'Service temporairement indisponible. Réessayez plus tard.';
    default:
      if (statusCode >= 500) {
        return 'Service temporairement indisponible. Réessayez plus tard.';
      }
      return 'Une erreur est survenue. Réessayez.';
  }
}

final _technicalPatterns = RegExp(
  r'(exception|stack\s*trace|sql|postgres|redis|dio|socketexception|'
  r'timeoutexception|errno|econnrefused|render\.com|internal server|'
  r'null check|typeerror|referenceerror|at Object\.|\#\d+\s)',
  caseSensitive: false,
);

/// True si le message serveur ne doit pas être affiché tel quel.
bool looksTechnical(String message) {
  final m = message.trim();
  if (m.isEmpty) return true;
  if (_technicalPatterns.hasMatch(m)) return true;
  if (RegExp(r'^erreur\s+\d{3}$', caseSensitive: false).hasMatch(m)) return true;
  if (m.contains('\n') && m.length > 120) return true;
  return false;
}

/// Messages API connus (anglais/technique) → français utilisateur.
String? mapKnownApiMessage(String message) {
  final lower = message.toLowerCase().trim();
  const known = {
    'invalid phone': 'Numéro de téléphone invalide.',
    'invalid code': 'Code incorrect. Vérifiez le SMS et réessayez.',
    'code expired': 'Code expiré. Demandez un nouveau code.',
    'too many requests': 'Trop de tentatives. Réessayez dans quelques instants.',
    'unauthorized': 'Session expirée. Veuillez vous reconnecter.',
    'forbidden': 'Accès non autorisé pour votre profil.',
    'not found': 'Élément introuvable.',
    'user not found': 'Compte introuvable.',
    'invalid token': 'Session expirée. Veuillez vous reconnecter.',
    'rate limit exceeded': 'Trop de demandes. Réessayez plus tard.',
    'partner not found': 'Partenaire introuvable.',
    'already exists': 'Cet élément existe déjà.',
  };
  for (final entry in known.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }
  return null;
}

/// Point d'entrée unique : toute erreur affichée à l'utilisateur doit passer ici.
String userFacingError(Object error, {String? fallback}) {
  if (error is ApiException) {
    final mapped = mapKnownApiMessage(error.message);
    if (mapped != null) return mapped;
    if (!looksTechnical(error.message)) {
      // Message déjà en français / métier côté API
      return error.message;
    }
    return messageForStatusCode(error.statusCode);
  }
  if (error is TimeoutException || error is SocketException || error is http.ClientException) {
    return describeNetworkError(error);
  }
  final asString = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  final mapped = mapKnownApiMessage(asString);
  if (mapped != null) return mapped;
  if (!looksTechnical(asString) && asString.length < 160) {
    return asString;
  }
  return fallback ?? describeNetworkError(error);
}
