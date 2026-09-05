import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage clé/valeur du PIN local (jamais en clair dans SharedPreferences).
abstract class PinStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecurePinStore implements PinStore {
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<String?> read(String key) async {
    try {
      return await _secure.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    await _secure.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _secure.delete(key: key);
    } catch (_) {}
  }
}

/// Store en mémoire pour les tests (pas de canal natif).
class MemoryPinStore implements PinStore {
  final Map<String, String> data;
  MemoryPinStore([Map<String, String>? initial]) : data = initial ?? {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

/// PIN de connexion local (4–6 chiffres), distinct du PIN de contrainte.
/// Hash SHA-256 + sel appareil — jamais le PIN en clair.
class LocalPinService {
  static const hashKey = 'login_pin_hash';
  static const saltKey = 'login_pin_salt';
  static const phoneKey = 'login_pin_phone';
  static const minDigits = 4;
  static const maxDigits = 6;

  final PinStore _store;

  LocalPinService({PinStore? store}) : _store = store ?? SecurePinStore();

  String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('safealert-login:$salt:$pin')).toString();

  Future<String> _ensureSalt() async {
    final existing = await _store.read(saltKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final rng = Random.secure();
    final salt = List.generate(16, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await _store.write(saltKey, salt);
    return salt;
  }

  Future<bool> hasPin() async {
    final h = await _store.read(hashKey);
    return h != null && h.isNotEmpty;
  }

  Future<String?> storedPhone() async {
    final p = await _store.read(phoneKey);
    if (p == null || p.isEmpty) return null;
    return p;
  }

  Future<void> setPin(String pin, {required String phone}) async {
    final cleaned = pin.replaceAll(RegExp(r'\D'), '');
    if (cleaned.length < minDigits || cleaned.length > maxDigits) {
      throw ArgumentError('Le code PIN doit contenir 4 à 6 chiffres');
    }
    final salt = await _ensureSalt();
    await _store.write(hashKey, _hash(cleaned, salt));
    await _store.write(phoneKey, phone);
  }

  Future<bool> verify(String pin) async {
    final hash = await _store.read(hashKey);
    final salt = await _store.read(saltKey);
    if (hash == null || hash.isEmpty || salt == null || salt.isEmpty) {
      return false;
    }
    final cleaned = pin.replaceAll(RegExp(r'\D'), '');
    if (cleaned.isEmpty) return false;
    return _hash(cleaned, salt) == hash;
  }

  Future<void> clear() async {
    await _store.delete(hashKey);
    await _store.delete(saltKey);
    await _store.delete(phoneKey);
  }
}
