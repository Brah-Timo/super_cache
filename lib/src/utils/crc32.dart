import 'dart:typed_data';

/// Stand-alone CRC-32 (IEEE 802.3 polynomial) utility.
///
/// Provides a fast, pure-Dart CRC-32 implementation used for data integrity
/// verification when reading cache entries from disk.
///
/// The precomputed lookup table is built once on first access and shared
/// across all calls.
abstract final class Crc32 {
  Crc32._();

  static final List<int> _table = _buildTable();

  static List<int> _buildTable() {
    final table = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var crc = i;
      for (var j = 0; j < 8; j++) {
        crc = (crc & 1) != 0 ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1);
      }
      table[i] = crc;
    }
    return table;
  }

  /// Computes the CRC-32 checksum of [data].
  ///
  /// Returns an unsigned 32-bit integer.
  static int compute(Uint8List data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc = _table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  /// Computes the CRC-32 of a [String]'s code units (no UTF-8 encoding).
  ///
  /// Suitable for hashing ASCII cache keys.
  static int computeString(String s) {
    var crc = 0xFFFFFFFF;
    for (var i = 0; i < s.length; i++) {
      crc = _table[(crc ^ (s.codeUnitAt(i) & 0xFF)) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  /// Verifies that `Crc32.compute(data) == expectedChecksum`.
  ///
  /// Returns `true` when the data is intact.
  static bool verify(Uint8List data, int expectedChecksum) =>
      compute(data) == expectedChecksum;

  /// Formats a CRC-32 value as an 8-character lowercase hexadecimal string.
  static String toHex(int crc) =>
      crc.toRadixString(16).padLeft(8, '0').toLowerCase();

  /// The precomputed lookup table (exposed for use in [IndexManager]).
  static List<int> get table => _table;
}
