import 'dart:typed_data';

/// Fast, non-cryptographic hash functions for internal use.
///
/// These hashes prioritize **speed** over collision resistance.
/// Do not use them for security-sensitive operations — use `crypto`
/// package hashes (SHA-256, HMAC) for that.
abstract final class HashUtils {
  HashUtils._();

  // ─────────────────────────────────────────────────────────────────────────
  // FNV-1a (32-bit)
  // ─────────────────────────────────────────────────────────────────────────

  static const int _fnvPrime32 = 16777619;
  static const int _fnvOffset32 = 2166136261;

  /// Computes a 32-bit FNV-1a hash of [data].
  ///
  /// FNV-1a is fast and has good distribution for short strings (cache keys).
  static int fnv1a32(Uint8List data) {
    var hash = _fnvOffset32;
    for (final byte in data) {
      hash ^= byte;
      hash = (hash * _fnvPrime32) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Computes a 32-bit FNV-1a hash of [string] without UTF-8 encoding.
  ///
  /// Uses code units directly — safe for ASCII cache keys.
  static int fnv1a32String(String string) {
    var hash = _fnvOffset32;
    for (var i = 0; i < string.length; i++) {
      hash ^= string.codeUnitAt(i) & 0xFF;
      hash = (hash * _fnvPrime32) & 0xFFFFFFFF;
    }
    return hash;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // xxHash32 (simplified)
  // ─────────────────────────────────────────────────────────────────────────

  static const int _xxPrime1 = 0x9E3779B1;
  static const int _xxPrime2 = 0x85EBCA77;
  static const int _xxPrime3 = 0xC2B2AE3D;
  static const int _xxPrime4 = 0x27D4EB2F;
  static const int _xxPrime5 = 0x165667B1;

  /// Computes a simplified xxHash32 of [data] with the given [seed].
  ///
  /// Faster than FNV-1a for larger inputs.
  static int xxHash32(Uint8List data, {int seed = 0}) {
    var h32 = 0;
    var i = 0;
    final len = data.length;

    if (len >= 16) {
      var v1 = (seed + _xxPrime1 + _xxPrime2) & 0xFFFFFFFF;
      var v2 = (seed + _xxPrime2) & 0xFFFFFFFF;
      var v3 = seed;
      var v4 = (seed - _xxPrime1) & 0xFFFFFFFF;

      while (i <= len - 16) {
        v1 = _round32(v1, _readUint32LE(data, i));
        i += 4;
        v2 = _round32(v2, _readUint32LE(data, i));
        i += 4;
        v3 = _round32(v3, _readUint32LE(data, i));
        i += 4;
        v4 = _round32(v4, _readUint32LE(data, i));
        i += 4;
      }

      h32 = (_rotl32(v1, 1) +
              _rotl32(v2, 7) +
              _rotl32(v3, 12) +
              _rotl32(v4, 18)) &
          0xFFFFFFFF;
    } else {
      h32 = (seed + _xxPrime5) & 0xFFFFFFFF;
    }

    h32 = (h32 + len) & 0xFFFFFFFF;

    while (i <= len - 4) {
      h32 = ((_rotl32(
                  (h32 + (_readUint32LE(data, i) * _xxPrime3 & 0xFFFFFFFF)) &
                      0xFFFFFFFF,
                  17) *
              _xxPrime4)) &
          0xFFFFFFFF;
      i += 4;
    }

    while (i < len) {
      h32 =
          (_rotl32((h32 + (data[i] * _xxPrime5 & 0xFFFFFFFF)) & 0xFFFFFFFF, 11) *
                  _xxPrime1) &
              0xFFFFFFFF;
      i++;
    }

    // Avalanche
    h32 ^= h32 >> 15;
    h32 = (h32 * _xxPrime2) & 0xFFFFFFFF;
    h32 ^= h32 >> 13;
    h32 = (h32 * _xxPrime3) & 0xFFFFFFFF;
    h32 ^= h32 >> 16;

    return h32;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dart's built-in hashCode for String (fast shortcut)
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a hash of [key] suitable for use as a bucket index.
  ///
  /// Uses Dart's built-in [String.hashCode] which is fast and well-distributed.
  static int bucketIndex(String key, int bucketCount) {
    final h = key.hashCode & 0x7FFFFFFF; // Remove sign bit
    return h % bucketCount;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Internal helpers
  // ─────────────────────────────────────────────────────────────────────────

  static int _readUint32LE(Uint8List data, int offset) =>
      data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);

  static int _round32(int acc, int input) =>
      (_rotl32((acc + (input * _xxPrime2 & 0xFFFFFFFF)) & 0xFFFFFFFF, 13) *
              _xxPrime1) &
      0xFFFFFFFF;

  static int _rotl32(int v, int n) =>
      ((v << n) | (v >> (32 - n))) & 0xFFFFFFFF;
}
