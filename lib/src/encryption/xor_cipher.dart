import 'dart:typed_data';

import 'package:super_cache/src/core/cache_exceptions.dart';
import 'package:super_cache/src/encryption/cipher.dart';

/// XOR stream cipher for maximum-speed, low-security encryption.
///
/// This cipher XOR's each byte of the plaintext with a byte derived from
/// a repeating key-stream (the key cycled to match the data length).
///
/// **⚠️ Security warning:**
/// XOR with a repeating key (Vigenère cipher) provides very weak security.
/// It is trivially breakable with ciphertext-only attacks when the key is
/// short relative to the data. Use this cipher only when:
/// - You need to obfuscate data at rest (not hide it from determined attackers).
/// - Encryption overhead is a genuine bottleneck (benchmark first).
/// - The threat model does not include adversaries who can observe ciphertext.
///
/// For real security, use [AesCipher] instead.
///
/// **Performance:** Near-zero overhead — the XOR loop is the only operation.
final class XorCipher implements SuperCacheCipher {
  /// Creates an [XorCipher] from [key].
  ///
  /// [key] must not be empty.
  XorCipher(List<int> key) {
    if (key.isEmpty) {
      throw const InvalidConfigException('XorCipher key must not be empty.');
    }
    _key = Uint8List.fromList(key);
  }

  late final Uint8List _key;

  @override
  String get algorithmName => 'XOR';

  @override
  Uint8List encrypt(Uint8List plaintext) => _xor(plaintext);

  @override
  Uint8List decrypt(Uint8List ciphertext) => _xor(ciphertext);

  // XOR is its own inverse: decrypt(encrypt(data)) == data
  Uint8List _xor(Uint8List data) {
    final result = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      result[i] = data[i] ^ _key[i % _key.length];
    }
    return result;
  }
}
