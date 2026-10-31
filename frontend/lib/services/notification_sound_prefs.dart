import 'package:shared_preferences/shared_preferences.dart';

/// Sons SafeAlert distinctifs (jamais le son système générique).
enum SafeAlertSoundId {
  siren,
  pulse,
  beacon,
}

extension SafeAlertSoundIdX on SafeAlertSoundId {
  String get storageKey => name;

  String get labelFr {
    switch (this) {
      case SafeAlertSoundId.siren:
        return 'Sirène SafeAlert';
      case SafeAlertSoundId.pulse:
        return 'Impulsion SafeAlert';
      case SafeAlertSoundId.beacon:
        return 'Balise SafeAlert';
    }
  }

  String get descriptionFr {
    switch (this) {
      case SafeAlertSoundId.siren:
        return 'Double tonalité urgente — recommandé pour les SOS';
      case SafeAlertSoundId.pulse:
        return 'Série de bips rythmés, reconnaissable immédiatement';
      case SafeAlertSoundId.beacon:
        return 'Motif musical SafeAlert (plus doux, toujours distinct)';
    }
  }

  /// Asset Flutter (audioplayers).
  String get assetPath {
    switch (this) {
      case SafeAlertSoundId.siren:
        return 'sounds/safealert_siren.wav';
      case SafeAlertSoundId.pulse:
        return 'sounds/safealert_pulse.wav';
      case SafeAlertSoundId.beacon:
        return 'sounds/safealert_beacon.wav';
    }
  }

  /// Android `res/raw` name (no extension).
  String get androidRawName {
    switch (this) {
      case SafeAlertSoundId.siren:
        return 'safealert_siren';
      case SafeAlertSoundId.pulse:
        return 'safealert_pulse';
      case SafeAlertSoundId.beacon:
        return 'safealert_beacon';
    }
  }

  /// iOS bundle sound for local + remote notifications.
  String get iosSoundFile {
    switch (this) {
      case SafeAlertSoundId.siren:
        return 'safealert_siren.caf';
      case SafeAlertSoundId.pulse:
        return 'safealert_pulse.caf';
      case SafeAlertSoundId.beacon:
        return 'safealert_beacon.caf';
    }
  }

  /// Dedicated Android channel (sticky — bump suffix if sound was wrong once).
  String get androidSosChannelId => 'safealert_sos_${name}_v2';
}

class NotificationSoundPrefs {
  NotificationSoundPrefs._();
  static final NotificationSoundPrefs instance = NotificationSoundPrefs._();
  factory NotificationSoundPrefs() => instance;

  static const _prefsKey = 'safealert_notification_sound';
  static const defaultSound = SafeAlertSoundId.siren;

  SafeAlertSoundId _current = defaultSound;
  bool _loaded = false;

  SafeAlertSoundId get current => _current;
  bool get loaded => _loaded;

  Future<SafeAlertSoundId> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _current = SafeAlertSoundId.values.firstWhere(
      (e) => e.storageKey == raw,
      orElse: () => defaultSound,
    );
    _loaded = true;
    return _current;
  }

  Future<void> setSound(SafeAlertSoundId id) async {
    _current = id;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, id.storageKey);
  }
}
