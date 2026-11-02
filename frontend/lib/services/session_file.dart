import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Session durable sur disque.
///
/// Sur iOS, le Keychain (flutter_secure_storage) et NSUserDefaults
/// (shared_preferences) perdent souvent le JWT après que le système a tué
/// l'app. Un fichier dans Application Support est relu au prochain lancement.
class SessionFile {
  static const _fileName = 'safealert_session.json';
  static Map<String, dynamic>? _cache;

  static Future<File?> _file() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> read() async {
    if (_cache != null) return Map<String, dynamic>.from(_cache!);
    final file = await _file();
    if (file == null || !await file.exists()) {
      _cache = {};
      return {};
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        _cache = Map<String, dynamic>.from(decoded);
        return Map<String, dynamic>.from(_cache!);
      }
    } catch (_) {}
    _cache = {};
    return {};
  }

  static Future<void> merge(Map<String, dynamic> patch) async {
    final current = await read();
    patch.forEach((key, value) {
      if (value == null) {
        current.remove(key);
      } else {
        current[key] = value;
      }
    });
    _cache = current;
    final file = await _file();
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(current), flush: true);
    } catch (e) {
      debugPrint('SessionFile write: $e');
    }
  }

  static Future<void> remove(Iterable<String> keys) async {
    final current = await read();
    for (final key in keys) {
      current.remove(key);
    }
    _cache = current;
    final file = await _file();
    if (file == null) return;
    try {
      await file.writeAsString(jsonEncode(current), flush: true);
    } catch (e) {
      debugPrint('SessionFile remove: $e');
    }
  }
}
