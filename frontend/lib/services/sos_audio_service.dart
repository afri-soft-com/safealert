import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'audio_clip_service.dart';

/// Optional 60 s audio clip recorded right after an SOS is sent, attached to
/// the alert so trust contacts can hear what is happening. Off by default:
/// the user turns it on in Settings, which is also when the microphone
/// permission is asked.
class SosAudioService {
  static final SosAudioService _instance = SosAudioService._();
  SosAudioService._();
  factory SosAudioService() => _instance;

  static const _prefKey = 'sos_audio_enabled';
  static const clipLength = Duration(seconds: 60);

  final ApiService _api = ApiService();
  bool _busy = false;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  /// Returns the stored value: false if the microphone was refused.
  Future<bool> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value && !await AudioClipService().ensurePermission()) {
      await prefs.setBool(_prefKey, false);
      return false;
    }
    await prefs.setBool(_prefKey, value);
    return value;
  }

  /// Fire-and-forget after a successful SOS. Never throws.
  Future<void> recordAndAttach(String incidentId) async {
    if (_busy || incidentId.isEmpty) return;
    try {
      if (!await isEnabled()) return;
      _busy = true;
      final clip = await AudioClipService().recordFor(clipLength);
      if (clip == null) return;
      await _api.post('/sos/$incidentId/evidence', {
        'consent_evidence': true,
        'evidence': [
          {'media_type': 'audio', 'data_url': clip.dataUrl},
        ],
      });
    } catch (e) {
      debugPrint('SOS audio: $e');
    } finally {
      _busy = false;
    }
  }

  /// Audio clips attached to an SOS (for the sender's trust contacts).
  Future<List<Map<String, dynamic>>> fetchClips(String incidentId) async {
    try {
      final res = await _api.get('/sos/$incidentId/evidence');
      final list = (res['evidence'] as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => e['media_type'] == 'audio' && (e['data_url'] ?? '').toString().startsWith('data:audio'))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
