import 'dart:typed_data';

/// A fast, sequential binary data reader that wraps a [Uint8List].
///
/// Maintains an internal read cursor ([offset]) and advances it with each
/// read call. All multi-byte integers are read as big-endian.
///
/// Throws a [RangeError] if a read would go past the end of the buffer,
/// making buffer-overrun bugs immediately visible.
final class BinaryReader {
  /// Creates a [BinaryReader] over the full [bytes] buffer.
  BinaryReader(Uint8List bytes)
      : _bytes = bytes,
        _byteData = ByteData.sublistView(bytes),
        _offset = 0;

  final Uint8List _bytes;
  final ByteData _byteData;
  int _offset;

  /// Current read position in the buffer.
  int get offset => _offset;

  /// Total length of the underlying buffer.
  int get length => _bytes.length;

  /// Number of bytes remaining to be read.
  int get remaining => _bytes.length - _offset;

  /// Whether the reader has reached the end of the buffer.
  bool get isAtEnd => _offset >= _bytes.length;

  // ── Bounds check ──────────────────────────────────────────────────────────

  void _checkAvailable(int count) {
    if (_offset + count > _bytes.length) {
      throw RangeError(
        'BinaryReader: attempted to read $count bytes at offset $_offset '
        'but only $remaining bytes remain in buffer of length ${_bytes.length}.',
      );
    }
  }

  // ── Primitive reads ───────────────────────────────────────────────────────

  /// Reads a single unsigned byte.
  int readByte() {
    _checkAvailable(1);
    return _bytes[_offset++];
  }

  /// Reads a signed 8-bit integer.
  int readInt8() {
    _checkAvailable(1);
    final v = _byteData.getInt8(_offset);
    _offset++;
    return v;
  }

  /// Reads an unsigned 16-bit integer (big-endian).
  int readUint16() {
    _checkAvailable(2);
    final v = _byteData.getUint16(_offset, Endian.big);
    _offset += 2;
    return v;
  }

  /// Reads a signed 16-bit integer (big-endian).
  int readInt16() {
    _checkAvailable(2);
    final v = _byteData.getInt16(_offset, Endian.big);
    _offset += 2;
    return v;
  }

  /// Reads an unsigned 32-bit integer (big-endian).
  int readUint32() {
    _checkAvailable(4);
    final v = _byteData.getUint32(_offset, Endian.big);
    _offset += 4;
    return v;
  }

  /// Reads a signed 32-bit integer (big-endian).
  int readInt32() {
    _checkAvailable(4);
    final v = _byteData.getInt32(_offset, Endian.big);
    _offset += 4;
    return v;
  }

  /// Reads a signed 64-bit integer (big-endian).
  int readInt64() {
    _checkAvailable(8);
    final v = _byteData.getInt64(_offset, Endian.big);
    _offset += 8;
    return v;
  }

  /// Reads an unsigned 64-bit integer (big-endian).
  int readUint64() => readInt64();

  /// Reads a 32-bit IEEE 754 float (big-endian).
  double readFloat32() {
    _checkAvailable(4);
    final v = _byteData.getFloat32(_offset, Endian.big);
    _offset += 4;
    return v;
  }

  /// Reads a 64-bit IEEE 754 double (big-endian).
  double readFloat64() {
    _checkAvailable(8);
    final v = _byteData.getFloat64(_offset, Endian.big);
    _offset += 8;
    return v;
  }

  /// Reads a boolean (0 = false, non-zero = true).
  bool readBool() => readByte() != 0;

  // ── Bulk reads ────────────────────────────────────────────────────────────

  /// Reads exactly [count] bytes and advances the cursor.
  Uint8List readBytes(int count) {
    _checkAvailable(count);
    final slice = Uint8List.sublistView(_bytes, _offset, _offset + count);
    _offset += count;
    return slice;
  }

  /// Reads a 32-bit length prefix, then that many bytes.
  Uint8List readLengthPrefixedBytes() {
    final length = readUint32();
    return readBytes(length);
  }

  /// Reads a UTF-8 string written by [BinaryWriter.writeString].
  ///
  /// The format is: uint32 byte-length, then that many UTF-8 bytes.
  String readString() {
    final byteLength = readUint32();
    final bytes = readBytes(byteLength);
    return _utf8Decode(bytes);
  }

  // ── Utility ───────────────────────────────────────────────────────────────

  /// Skips [count] bytes without reading them.
  void skip(int count) {
    _checkAvailable(count);
    _offset += count;
  }

  /// Returns a view of the remaining unread bytes without advancing the cursor.
  Uint8List peekRemaining() =>
      Uint8List.sublistView(_bytes, _offset, _bytes.length);

  // ── UTF-8 ─────────────────────────────────────────────────────────────────

  String _utf8Decode(Uint8List bytes) {
    // Fast path: all ASCII
    var allAscii = true;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] > 127) {
        allAscii = false;
        break;
      }
    }
    if (allAscii) return String.fromCharCodes(bytes);

    // General path: decode UTF-8 code points
    final chars = <int>[];
    var i = 0;
    while (i < bytes.length) {
      final b = bytes[i];
      if (b & 0x80 == 0) {
        chars.add(b);
        i++;
      } else if (b & 0xE0 == 0xC0) {
        chars.add(((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
        i += 2;
      } else if (b & 0xF0 == 0xE0) {
        chars.add(
          ((b & 0x0F) << 12) |
              ((bytes[i + 1] & 0x3F) << 6) |
              (bytes[i + 2] & 0x3F),
        );
        i += 3;
      } else {
        chars.add(
          ((b & 0x07) << 18) |
              ((bytes[i + 1] & 0x3F) << 12) |
              ((bytes[i + 2] & 0x3F) << 6) |
              (bytes[i + 3] & 0x3F),
        );
        i += 4;
      }
    }
    return String.fromCharCodes(chars);
  }
}
