import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:super_cache/src/core/cache_exceptions.dart';
import 'package:super_cache/src/encryption/cipher.dart';

/// AES-256-GCM authenticated encryption cipher for super_cache.
///
/// **Security properties:**
/// - Key: 256-bit (32 bytes) — brute-force resistant.
/// - Mode: GCM (Galois/Counter Mode) — provides both confidentiality and
///   authenticity. Any tampered ciphertext is detected and rejected.
/// - IV/Nonce: 96-bit (12 bytes) — randomly generated per encryption call.
///   Using a fresh nonce each time prevents nonce-reuse attacks.
/// - Auth tag: 128-bit (16 bytes) — appended to the ciphertext.
///
/// **Wire format:**
/// ```
/// [ 12 bytes ] IV (random nonce)
/// [ n bytes  ] AES-256-CTR encrypted payload
/// [ 16 bytes ] GCM authentication tag
/// ```
/// Total overhead per value: **28 bytes**.
///
/// **Usage:**
/// ```dart
/// final key = AesCipher.generateKey(); // save this securely!
/// await SuperCache.init(
///   config: CacheConfig(encryptionKey: key),
/// );
/// ```
final class AesCipher implements SuperCacheCipher {
  /// Creates an [AesCipher] with the given 32-byte [key].
  ///
  /// Throws [InvalidKeyException] if [key] is not exactly 32 bytes.
  AesCipher(List<int> key) {
    if (key.length != 32) {
      throw InvalidKeyException(32, key.length);
    }
    _key = Uint8List.fromList(key);
  }

  late final Uint8List _key;

  static final math.Random _random = math.Random.secure();

  @override
  String get algorithmName => 'AES-256-GCM';

  // ─────────────────────────────────────────────────────────────────────────
  // Encrypt
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Uint8List encrypt(Uint8List plaintext) {
    try {
      final iv = _generateIv();
      final cipher = _buildCipher(iv, forEncryption: true);

      // Output buffer: payload + 16-byte auth tag
      final outputLen = plaintext.length + 16;
      final output = Uint8List(outputLen);

      var offset = cipher.processBytes(plaintext, 0, plaintext.length, output, 0);
      offset += cipher.doFinal(output, offset);

      // Prepend IV → [ IV | ciphertext+tag ]
      final result = Uint8List(12 + outputLen);
      result.setRange(0, 12, iv);
      result.setRange(12, 12 + outputLen, output);
      return result;
    } catch (e) {
      if (e is SuperCacheException) rethrow;
      throw CacheEncryptionException(
        'AES-256-GCM encryption failed: $e',
        cause: e,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Decrypt
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Uint8List decrypt(Uint8List ciphertext) {
    if (ciphertext.length < 28) {
      throw CacheEncryptionException(
        'Ciphertext too short: ${ciphertext.length} bytes. '
        'Minimum is 28 bytes (12 IV + 16 auth tag).',
      );
    }

    try {
      final iv = ciphertext.sublist(0, 12);
      final payload = ciphertext.sublist(12);

      final cipher = _buildCipher(iv, forEncryption: false);

      final plaintext = Uint8List(payload.length - 16);
      final offset = cipher.processBytes(payload, 0, payload.length, plaintext, 0);
      cipher.doFinal(plaintext, offset);

      return plaintext;
    } on InvalidCipherTextException catch (e) {
      throw CacheEncryptionException(
        'AES-256-GCM authentication tag mismatch — '
        'the data may be corrupted or tampered: $e',
        cause: e,
      );
    } catch (e) {
      if (e is SuperCacheException) rethrow;
      throw CacheEncryptionException(
        'AES-256-GCM decryption failed: $e',
        cause: e,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Key generation
  // ─────────────────────────────────────────────────────────────────────────

  /// Generates a cryptographically random 32-byte AES-256 key.
  ///
  /// Store this key securely (e.g. in `flutter_secure_storage`) and never
  /// hard-code it in source files.
  static List<int> generateKey() {
    return List<int>.generate(32, (_) => _random.nextInt(256));
  }

  /// Derives a 32-byte key from a [password] and [salt] using PBKDF2-SHA256.
  ///
  /// Use a randomly generated 16-byte [salt] stored alongside the encrypted data.
  /// [iterations] defaults to 100 000 — sufficient for most mobile workloads.
  static List<int> deriveKey(
    String password,
    List<int> salt, {
    int iterations = 100000,
  }) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(
      Pbkdf2Parameters(Uint8List.fromList(salt), iterations, 32),
    );
    final passwordBytes = Uint8List.fromList(password.codeUnits);
    return pbkdf2.process(passwordBytes).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Internal helpers
  // ─────────────────────────────────────────────────────────────────────────

  GCMBlockCipher _buildCipher(Uint8List iv, {required bool forEncryption}) {
    final params = AEADParameters(
      KeyParameter(_key),
      128, // auth tag length in bits
      iv,
      Uint8List(0), // AAD — empty
    );
    return GCMBlockCipher(AESEngine())..init(forEncryption, params);
  }

  Uint8List _generateIv() =>
      Uint8List.fromList(List<int>.generate(12, (_) => _random.nextInt(256)));
}
