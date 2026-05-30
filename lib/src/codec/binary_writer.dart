import 'dart:typed_data';

/// A fast, sequential binary data writer backed by a growable byte list.
///
/// Uses big-endian byte order throughout for cross-platform determinism.
///
/// This class is not thread-safe and is intended to be used on a single
/// isolate. Create a new instance per encode operation.
final class BinaryWriter {
  /// Creates a [BinaryWriter] with an optional initial buffer [capacity].
  BinaryWriter({int capacity = 64}) : _buffer = Uint8List(capacity), _length = 0;

  Uint8List _buffer;
  int _length;

  /// The number of bytes currently written.
  int get length => _length;

  // ── Internal growth ───────────────────────────────────────────────────────

  void _ensureCapacity(int additionalBytes) {
    final required = _length + additionalBytes;
    if (required <= _buffer.length) return;

    // Double the buffer until it fits — amortised O(1) per write.
    var newCapacity = _buffer.length;
    while (newCapacity < required) {
      newCapacity = newCapacity == 0 ? 64 : newCapacity * 2;
    }
    final newBuffer = Uint8List(newCapacity);
    newBuffer.setRange(0, _length, _buffer);
    _buffer = newBuffer;
  }

  // ── Primitive writes ──────────────────────────────────────────────────────

  /// Writes a single unsigned byte.
  void writeByte(int value) {
    _ensureCapacity(1);
    _buffer[_length++] = value & 0xFF;
  }

  /// Writes a signed 8-bit integer.
  void writeInt8(int value) => writeByte(value);

  /// Writes an unsigned 16-bit integer (big-endian).
  void writeUint16(int value) {
    _ensureCapacity(2);
    _buffer[_length++] = (value >> 8) & 0xFF;
    _buffer[_length++] = value & 0xFF;
  }

  /// Writes a signed 16-bit integer (big-endian).
  void writeInt16(int value) => writeUint16(value & 0xFFFF);

  /// Writes an unsigned 32-bit integer (big-endian).
  void writeUint32(int value) {
    _ensureCapacity(4);
    _buffer[_length++] = (value >> 24) & 0xFF;
    _buffer[_length++] = (value >> 16) & 0xFF;
    _buffer[_length++] = (value >> 8) & 0xFF;
    _buffer[_length++] = value & 0xFF;
  }

  /// Writes a signed 32-bit integer (big-endian).
  void writeInt32(int value) => writeUint32(value);

  /// Writes a signed 64-bit integer (big-endian).
  void writeInt64(int value) {
    _ensureCapacity(8);
    final bd = ByteData(8)..setInt64(0, value, Endian.big);
    final bytes = bd.buffer.asUint8List();
    _buffer.setRange(_length, _length + 8, bytes);
    _length += 8;
  }

  /// Writes an unsigned 64-bit integer (big-endian).
  void writeUint64(int value) => writeInt64(value);

  /// Writes a 32-bit IEEE 754 float (big-endian).
  void writeFloat32(double value) {
    _ensureCapacity(4);
    final bd = ByteData(4)..setFloat32(0, value, Endian.big);
    final bytes = bd.buffer.asUint8List();
    _buffer.setRange(_length, _length + 4, bytes);
    _length += 4;
  }

  /// Writes a 64-bit IEEE 754 double (big-endian).
  void writeFloat64(double value) {
    _ensureCapacity(8);
    final bd = ByteData(8)..setFloat64(0, value, Endian.big);
    final bytes = bd.buffer.asUint8List();
    _buffer.setRange(_length, _length + 8, bytes);
    _length += 8;
  }

  /// Writes a boolean as a single byte (0x01 = true, 0x00 = false).
  void writeBool(bool value) => writeByte(value ? 1 : 0);

  // ── Bulk writes ───────────────────────────────────────────────────────────

  /// Appends [bytes] verbatim — no length prefix is written.
  void writeBytes(Uint8List bytes) {
    _ensureCapacity(bytes.length);
    _buffer.setRange(_length, _length + bytes.length, bytes);
    _length += bytes.length;
  }

  /// Writes a [Uint8List] preceded by its 32-bit length.
  void writeLengthPrefixedBytes(Uint8List bytes) {
    writeUint32(bytes.length);
    writeBytes(bytes);
  }

  /// Writes a UTF-8 encoded string preceded by its 32-bit byte length.
  void writeString(String value) {
    final encoded = _utf8Encode(value);
    writeUint32(encoded.length);
    writeBytes(encoded);
  }

  // ── Output ────────────────────────────────────────────────────────────────

  /// Returns the bytes written so far as a compact [Uint8List].
  Uint8List toBytes() => Uint8List.sublistView(_buffer, 0, _length);

  // ── UTF-8 ─────────────────────────────────────────────────────────────────

  /// Pure-Dart UTF-8 encoder — avoids `dart:convert` import overhead for
  /// the common ASCII path (which covers most cache keys and enum strings).
  Uint8List _utf8Encode(String s) {
    // Fast path: all ASCII
    var allAscii = true;
    for (var i = 0; i < s.length; i++) {
      if (s.codeUnitAt(i) > 127) {
        allAscii = false;
        break;
      }
    }
    if (allAscii) {
      final out = Uint8List(s.length);
      for (var i = 0; i < s.length; i++) {
        out[i] = s.codeUnitAt(i);
      }
      return out;
    }

    // General path: multi-byte code-points
    final result = <int>[];
    for (final rune in s.runes) {
      if (rune < 0x80) {
        result.add(rune);
      } else if (rune < 0x800) {
        result
          ..add(0xC0 | (rune >> 6))
          ..add(0x80 | (rune & 0x3F));
      } else if (rune < 0x10000) {
        result
          ..add(0xE0 | (rune >> 12))
          ..add(0x80 | ((rune >> 6) & 0x3F))
          ..add(0x80 | (rune & 0x3F));
      } else {
        result
          ..add(0xF0 | (rune >> 18))
          ..add(0x80 | ((rune >> 12) & 0x3F))
          ..add(0x80 | ((rune >> 6) & 0x3F))
          ..add(0x80 | (rune & 0x3F));
      }
    }
    return Uint8List.fromList(result);
  }
}
