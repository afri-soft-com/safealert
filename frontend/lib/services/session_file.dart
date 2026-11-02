import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Session durable sur disque.
///
/// Sur iOS, le Keychain et NSUserDefaults perdent le JWT quand le système
/// tue l'app. Le fichier est dans le dossier Documents du conteneur, qui
/// survit à cette fermeture.
class SessionFile {
  static const _fileName = 'safealert_session.json';
  static Map<String, dynamic>? _cache;

  static bool get _inTest {
    if (kIsWeb) return true;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return true;
    try {
      return WidgetsBinding.instance.runtimeType.toString().contains('Test');
    } catch (_) {
      return false;
    }
  }

  static Future<Directory?> _dir() async {
    if (_inTest) return null;
    try {
      if (Platform.isIOS) {
        final docs = Directory('${Directory.systemTemp.parent.path}/Documents');
        if (!await docs.exists()) await docs.create(recursive: true);
        return docs;
      }
    } catch (_) {}
    try {
      final dir = await getApplicationDocumentsDirectory();
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  static Future<File?> _file() async {
    final dir = await _dir();
    if (dir == null) return null;
    return File('${dir.path}/$_fileName');
  }

  static Future<Map<String, dynamic>> read() async {
    if (_inTest) return {};
    if (_cache != null) return Map<String, dynamic>.from(_cache!);
    final file = await _file();
    if (file == null) return {};
    if (!await file.exists()) {
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
    if (_inTest) return;
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
