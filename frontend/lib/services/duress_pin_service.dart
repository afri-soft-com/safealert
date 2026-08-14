import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// PIN de contrainte distinct du code camouflage calculatrice (1234=).
/// Entré sur la calculatrice, il déclenche un SOS silencieux sans déverrouiller.
class DuressPinService {
  DuressPinService._();
  static final DuressPinService instance = DuressPinService._();
  factory DuressPinService() => instance;

  static const _hashKey = 'duress_pin_hash';
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String _hash(String pin) => sha256.convert(utf8.encode('safealert-duress:$pin')).toString();

  Future<bool> hasPin() async {
    final h = await _secure.read(key: _hashKey);
    return h != null && h.isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    final cleaned = pin.replaceAll(RegExp(r'\D'), '');
    if (cleaned.length < 4 || cleaned.length > 8) {
      throw ArgumentError('Le code doit contenir entre 4 et 8 chiffres');
    }
    // Never equal to camouflage unlock digits
    if (cleaned == '1234') {
      throw ArgumentError('Choisissez un code différent du déverrouillage calculatrice');
    }
    await _secure.write(key: _hashKey, value: _hash(cleaned));
  }

  Future<void> clearPin() async {
    await _secure.delete(key: _hashKey);
  }

  /// Returns true if [displayDigits] matches the configured duress PIN.
  Future<bool> matches(String displayDigits) async {
    final h = await _secure.read(key: _hashKey);
    if (h == null || h.isEmpty) return false;
    final cleaned = displayDigits.replaceAll(RegExp(r'\D'), '');
    if (cleaned.isEmpty) return false;
    return _hash(cleaned) == h;
  }
}
