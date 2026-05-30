import 'dart:typed_data';

/// Utility functions for working with raw byte arrays.
///
/// All functions are pure (no side effects) and operate on [Uint8List].
abstract final class ByteUtils {
  ByteUtils._();

  // ─────────────────────────────────────────────────────────────────────────
  // Comparison
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns `true` if [a] and [b] contain identical bytes.
  ///
  /// Runs in O(n) time.  For security-sensitive comparisons (e.g. auth tags)
  /// use [constantTimeEqual] instead to prevent timing attacks.
  static bool equal(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Constant-time byte-array comparison.
  ///
  /// Always takes the same number of operations regardless of where the first
  /// differing byte is, preventing timing side-channel attacks.
  static bool constantTimeEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Concatenation
  // ─────────────────────────────────────────────────────────────────────────

  /// Concatenates [parts] into a single [Uint8List].
  static Uint8List concat(List<Uint8List> parts) {
    final totalLen = parts.fold<int>(0, (s, p) => s + p.length);
    final result = Uint8List(totalLen);
    var offset = 0;
    for (final part in parts) {
      result.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Slicing
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a zero-copy view of [bytes] from [start] (inclusive) to [end]
  /// (exclusive).
  ///
  /// Equivalent to `bytes.sublist(start, end)` but avoids copying when the
  /// underlying buffer is not mutated.
  static Uint8List view(Uint8List bytes, int start, [int? end]) =>
      Uint8List.sublistView(bytes, start, end);

  // ─────────────────────────────────────────────────────────────────────────
  // Conversion
  // ─────────────────────────────────────────────────────────────────────────

  /// Converts [bytes] to a lowercase hexadecimal string.
  static String toHex(Uint8List bytes) {
    final buf = StringBuffer();
    for (final b in bytes) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  /// Parses a lowercase hexadecimal string into a [Uint8List].
  static Uint8List fromHex(String hex) {
    if (hex.length.isOdd) throw ArgumentError('Hex string has odd length.');
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  /// Converts an [int] to a big-endian [Uint8List] of [length] bytes.
  static Uint8List intToBytes(int value, int length) {
    final result = Uint8List(length);
    for (var i = length - 1; i >= 0; i--) {
      result[i] = value & 0xFF;
      value >>= 8;
    }
    return result;
  }

  /// Converts a big-endian [Uint8List] to an unsigned [int].
  static int bytesToInt(Uint8List bytes) {
    var result = 0;
    for (final b in bytes) {
      result = (result << 8) | b;
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Zeroing (for key material)
  // ─────────────────────────────────────────────────────────────────────────

  /// Overwrites [bytes] with zeros.
  ///
  /// Call this after you are done with sensitive key material to reduce the
  /// window during which the key is readable in memory.
  static void zeroOut(Uint8List bytes) {
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }
}
