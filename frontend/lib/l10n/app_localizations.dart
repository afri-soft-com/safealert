import 'package:flutter/material.dart';

/// Lightweight i18n for SafeAlert — FR / LN (Lingala) / SW (Swahili) / EN.
class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static const supportedLocales = [
    Locale('fr'),
    Locale('ln'),
    Locale('sw'),
    Locale('en'),
  ];

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('fr'));
  }

  static const _strings = <String, Map<String, String>>{
    'appName': {
      'fr': 'SafeAlert',
      'ln': 'SafeAlert',
      'sw': 'SafeAlert',
      'en': 'SafeAlert',
    },
    'sos': {
      'fr': 'SOS',
      'ln': 'SOS',
      'sw': 'SOS',
      'en': 'SOS',
    },
    'imSafe': {
      'fr': 'Je suis en sécurité',
      'ln': 'Nazali na boboto',
      'sw': 'Niko salama',
      'en': "I'm safe",
    },
    'safeTrip': {
      'fr': 'Trajet sécurisé',
      'ln': 'Mobembo ya boboto',
      'sw': 'Safari salama',
      'en': 'Safe trip',
    },
    'annuaire': {
      'fr': "Annuaire d'urgence",
      'ln': 'Ba nimero ya bobangi',
      'sw': 'Nambari za dharura',
      'en': 'Emergency directory',
    },
    'call': {
      'fr': 'Appeler',
      'ln': 'Benga',
      'sw': 'Piga simu',
      'en': 'Call',
    },
    'contacts': {
      'fr': 'Contacts de confiance',
      'ln': 'Ba contact ya bolingo',
      'sw': 'Anwani za uaminifu',
      'en': 'Trust contacts',
    },
    'checkInSent': {
      'fr': 'Votre cercle de confiance a été notifié.',
      'ln': 'Ba contact nayo bayebisi.',
      'sw': 'Mzunguko wako wa uaminifu umearifiwa.',
      'en': 'Your trust circle has been notified.',
    },
    'falseAlarm': {
      'fr': 'Fausse alerte — contacts notifiés',
      'ln': 'Alerte ya lokuta — bayebisi',
      'sw': 'Tahadhari ya uwongo — wamearifiwa',
      'en': 'False alarm — contacts notified',
    },
    'trustZones': {
      'fr': 'Zones de confiance',
      'ln': 'Ba zone ya bolingo',
      'sw': 'Maeneo salama',
      'en': 'Trust zones',
    },
    'neighborhood': {
      'fr': 'Veille de quartier',
      'ln': 'Kobatela quartier',
      'sw': 'Ulinzi wa mtaa',
      'en': 'Neighborhood watch',
    },
    'language': {
      'fr': 'Langue',
      'ln': 'Lokota',
      'sw': 'Lugha',
      'en': 'Language',
    },
    'settings': {
      'fr': 'Paramètres',
      'ln': 'Ba paramètre',
      'sw': 'Mipangilio',
      'en': 'Settings',
    },
    'premium': {
      'fr': 'Premium',
      'ln': 'Premium',
      'sw': 'Premium',
      'en': 'Premium',
    },
  };

  String t(String key) {
    final map = _strings[key];
    if (map == null) return key;
    return map[locale.languageCode] ?? map['fr'] ?? key;
  }

  String get appName => t('appName');
  String get sos => t('sos');
  String get imSafe => t('imSafe');
  String get safeTrip => t('safeTrip');
  String get annuaire => t('annuaire');
  String get call => t('call');
  String get contacts => t('contacts');
  String get checkInSent => t('checkInSent');
  String get falseAlarm => t('falseAlarm');
  String get trustZones => t('trustZones');
  String get neighborhood => t('neighborhood');
  String get language => t('language');
  String get settings => t('settings');
  String get premium => t('premium');
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['fr', 'ln', 'sw', 'en'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async => AppLocalizations(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) => false;
}
