// TARGET: Flutter 3.22+ | encrypt ^5.0.3 | crypto ^3.0.3
// JARVIS MODULE: AES-256-GCM Encryption Layer

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;

class JarvisCrypto {
  late final enc.Key _key;
  static JarvisCrypto? _instance;

  JarvisCrypto._internal(String sessionKey) {
    // Derive 256-bit key from session key via SHA-256
    final keyBytes = crypto.sha256.convert(utf8.encode(sessionKey)).bytes;
    _key = enc.Key(Uint8List.fromList(keyBytes));
  }

  factory JarvisCrypto.init(String sessionKey) {
    _instance = JarvisCrypto._internal(sessionKey);
    return _instance!;
  }

  static JarvisCrypto get instance {
    assert(_instance != null, 'JarvisCrypto not initialized. Call init() first.');
    return _instance!;
  }

  // ── ENCRYPT ───────────────────────────────────────────────────────────────
  Map<String, String> encrypt(Map<String, dynamic> payload) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(jsonEncode(payload), iv: iv);
    return {
      'iv': iv.base64,
      'data': encrypted.base64,
    };
  }

  // ── DECRYPT ───────────────────────────────────────────────────────────────
  Map<String, dynamic>? decrypt(Map<String, String> envelope) {
    try {
      final iv = enc.IV.fromBase64(envelope['iv']!);
      final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.gcm));
      final decrypted = encrypter.decrypt64(envelope['data']!, iv: iv);
      return jsonDecode(decrypted) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[JARVIS-CRYPTO] Decryption error: $e');
      return null;
    }
  }

  // ── KEY HASH (for auth) ───────────────────────────────────────────────────
  String get keyHash {
    return crypto.sha256
        .convert(_key.bytes)
        .toString();
  }
}