import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Session durable.
///
/// `SharedPreferences.getInstance` relit iOS via `persistentDomain`, qui
/// revient souvent vide après que le système a tué l'app. Les clés sont
/// pourtant toujours dans UserDefaults. `SharedPreferencesAsync` les relit
/// une par une (`object(forKey:)`), ce qui survit à cette fermeture.
/// Un fichier dans Documents sert de second exemplaire.
class SessionFile {
  static const _fileName = 'safealert_session.json';
  static const _blobKey = 'safealert_session_json';
  static const _channel = MethodChannel('safealert/session');
  static Map<String, dynamic>? _cache;

  static const _legacyKeys = <String, String>{
    'token': 'flutter.auth_token',
    'deviceId': 'flutter.device_id',
    'user': 'flutter.safealert_cached_user_v1',
    'pinHash': 'flutter.pin_mirror_v1_login_pin_hash',
    'pinSalt': 'flutter.pin_mirror_v1_login_pin_salt',
    'pinPhone': 'flutter.pin_mirror_v1_login_pin_phone',
  };

  static bool get _inTest {
    if (kIsWeb) return true;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return true;
    try {
      return WidgetsBinding.instance.runtimeType.toString().contains('Test');
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> read() async {
    if (_inTest) return {};
    if (_cache != null) return Map<String, dynamic>.from(_cache!);

    final layers = <Map<String, dynamic>>[];
    final legacy = await _readLegacy();
    if (legacy.isNotEmpty) layers.add(legacy);
    for (final file in await _files()) {
      final stored = await _readOne(file);
      if (stored.isNotEmpty) layers.add(stored);
    }
    final blob = await _readBlob();
    if (blob.isNotEmpty) layers.add(blob);
    final native = await _readNative();
    if (native == null && layers.isEmpty) return {};
    if (native != null && native.isNotEmpty) layers.add(native);

    final merged = <String, dynamic>{};
    for (final layer in layers) {
      layer.forEach((key, value) {
        if (value == null) return;
        if (value is String && value.isEmpty) return;
        merged[key] = value;
      });
    }
    _cache = merged;
    final nativeMap = native ?? const <String, dynamic>{};
    if (merged.isNotEmpty && jsonEncode(nativeMap) != jsonEncode(merged)) {
      await _persist(merged);
    }
    return Map<String, dynamic>.from(merged);
  }

  static Future<void> merge(Map<String, dynamic> patch) async {
    if (_inTest) return;
    final current = await read();
    patch.forEach((key, value) {
      if (value == null) {
        current.remove(key);
      } else {
        current[key] = value;
      }
    });
    _cache = current;
    await _persist(current);
  }

  static Future<void> remove(Iterable<String> keys) async {
    if (_inTest) return;
    final current = await read();
    for (final key in keys) {
      current.remove(key);
    }
    _cache = current;
    await _persist(current);
  }

  static Future<Map<String, dynamic>?> _readNative() async {
    if (_inTest || !Platform.isIOS) return {};
    try {
      final raw = await _channel.invokeMethod<String>('read');
      return _decodeMap(raw);
    } catch (e) {
      debugPrint('SessionFile native read: $e');
      return null;
    }
  }

  static Future<void> _writeNative(String encoded) async {
    if (_inTest || !Platform.isIOS) return;
    try {
      await _channel.invokeMethod<bool>('write', encoded);
    } catch (e) {
      debugPrint('SessionFile native write: $e');
    }
  }

  static Future<void> _persist(Map<String, dynamic> data) async {
    final encoded = jsonEncode(data);
    await _writeNative(encoded);
    try {
      await SharedPreferencesAsync().setString(_blobKey, encoded);
    } catch (e) {
      debugPrint('SessionFile defaults: $e');
    }
    for (final file in await _files()) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(encoded, flush: true);
      } catch (e) {
        debugPrint('SessionFile write: $e');
      }
    }
  }

  static Future<Map<String, dynamic>> _readBlob() async {
    try {
      final raw = await SharedPreferencesAsync().getString(_blobKey);
      return _decodeMap(raw);
    } catch (e) {
      debugPrint('SessionFile blob: $e');
      return {};
    }
  }

  static Future<Map<String, dynamic>> _readLegacy() async {
    final out = <String, dynamic>{};
    try {
      final prefs = SharedPreferencesAsync();
      for (final entry in _legacyKeys.entries) {
        final raw = await prefs.getString(entry.value);
        if (raw == null || raw.isEmpty) continue;
        if (entry.key == 'user') {
          final user = _decodeMap(raw);
          if (user.isNotEmpty) out['user'] = user;
        } else {
          out[entry.key] = raw;
        }
      }
    } catch (e) {
      debugPrint('SessionFile legacy: $e');
    }
    return out;
  }

  static Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {};
  }

  static Future<List<File>> _files() async {
    final out = <File>[];
    try {
      final docs = await getApplicationDocumentsDirectory();
      out.add(File('${docs.path}/$_fileName'));
    } catch (_) {}
    try {
      final support = await getApplicationSupportDirectory();
      out.add(File('${support.path}/$_fileName'));
    } catch (_) {}
    return out;
  }

  static Future<Map<String, dynamic>> _readOne(File file) async {
    try {
      if (!await file.exists()) return {};
      return _decodeMap(await file.readAsString());
    } catch (_) {
      return {};
    }
  }
}
