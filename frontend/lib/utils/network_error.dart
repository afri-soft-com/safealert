import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

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
