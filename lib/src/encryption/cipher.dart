import 'dart:typed_data';

/// Abstract contract for super_cache encryption backends.
///
/// Implement this interface to plug in any symmetric cipher.
/// The two built-in implementations are:
/// - [AesCipher]  — AES-256-GCM (authenticated encryption, recommended).
/// - [XorCipher]  — XOR stream cipher (maximum speed, minimal security).
///
/// ⚠️ Both encrypt and decrypt must be **pure functions** with respect
/// to the ciphertext — i.e. `decrypt(encrypt(data)) == data` always.
abstract interface class SuperCacheCipher {
  /// Encrypts [plaintext] and returns the ciphertext.
  ///
  /// The returned bytes may be longer than [plaintext] to accommodate
  /// an IV, nonce, or authentication tag.
  Uint8List encrypt(Uint8List plaintext);

  /// Decrypts [ciphertext] and returns the original plaintext.
  ///
  /// Throws [CacheEncryptionException] if the ciphertext is invalid
  /// or tampered (when using authenticated encryption).
  Uint8List decrypt(Uint8List ciphertext);

  /// Human-readable name of this cipher (used in debug output).
  String get algorithmName;
}

/// Null cipher — returns data unchanged.
///
/// Used internally when [CacheConfig.encryptionKey] is `null`.
/// Never expose this to users.
final class NullCipher implements SuperCacheCipher {
  /// Creates a [NullCipher].
  const NullCipher();

  @override
  Uint8List encrypt(Uint8List plaintext) => plaintext;

  @override
  Uint8List decrypt(Uint8List ciphertext) => ciphertext;

  @override
  String get algorithmName => 'none';
}
