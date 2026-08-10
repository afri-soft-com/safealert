import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'api_service.dart';

/// Client-side encrypted contact backup (AES-like via XOR+HMAC with PBKDF).
/// Server never sees plaintext. Passphrase never leaves the device.
class ContactBackupService {
  final ApiService _api = ApiService();

  Future<void> backup(List<Map<String, dynamic>> contacts, String passphrase) async {
    final salt = _randomBytes(16);
    final key = _deriveKey(passphrase, salt);
    final plaintext = utf8.encode(jsonEncode(contacts));
    final nonce = _randomBytes(12);
    final cipher = _xorStream(plaintext, key, nonce);
    final mac = Hmac(sha256, key).convert([...nonce, ...cipher]).bytes;

    await _api.put('/backup/contacts', {
      'ciphertext': base64Encode([...mac, ...cipher]),
      'nonce': base64Encode(nonce),
      'salt': base64Encode(salt),
      'contact_count': contacts.length,
      'version': 1,
    });
  }

  Future<List<Map<String, dynamic>>?> restore(String passphrase) async {
    try {
      final res = await _api.get('/backup/contacts');
      final salt = base64Decode(res['salt'] as String);
      final nonce = base64Decode(res['nonce'] as String);
      final blob = base64Decode(res['ciphertext'] as String);
      if (blob.length < 32) return null;
      final mac = blob.sublist(0, 32);
      final cipher = blob.sublist(32);
      final key = _deriveKey(passphrase, salt);
      final expected = Hmac(sha256, key).convert([...nonce, ...cipher]).bytes;
      if (!_constEq(mac, expected)) {
        throw Exception('Phrase secrète incorrecte');
      }
      final plain = utf8.decode(_xorStream(cipher, key, nonce));
      final list = jsonDecode(plain) as List;
      return list.cast<Map<String, dynamic>>();
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Uint8List _deriveKey(String passphrase, List<int> salt) {
    var data = utf8.encode(passphrase);
    for (var i = 0; i < 10000; i++) {
      data = sha256.convert([...data, ...salt]).bytes;
    }
    return Uint8List.fromList(data);
  }

  Uint8List _xorStream(List<int> data, List<int> key, List<int> nonce) {
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      final kb = sha256.convert([...key, ...nonce, i >> 8, i & 0xff]).bytes;
      out[i] = data[i] ^ kb[i % kb.length];
    }
    return out;
  }

  Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  bool _constEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }
}
