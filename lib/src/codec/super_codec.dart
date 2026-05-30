import 'dart:typed_data';

import 'package:super_cache/src/codec/binary_reader.dart';
import 'package:super_cache/src/codec/binary_writer.dart';
import 'package:super_cache/src/codec/type_registry.dart';
import 'package:super_cache/src/core/cache_exceptions.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Type IDs  (1 byte each — values 0x00–0xDC reserved for built-ins)
// ─────────────────────────────────────────────────────────────────────────────

/// Wire-format type identifiers used by [SuperCodec].
///
/// Each built-in Dart type is assigned a compact 1-byte ID so that the codec
/// never writes a full type name as a string (saving 5–30 bytes per value).
/// Custom objects use [TypeIds.customObject] followed by the adapter's typeId.
abstract final class TypeIds {
  /// Null value.
  static const int nullType = 0x00;

  /// bool `true`.
  static const int boolTrue = 0x01;

  /// bool `false`.
  static const int boolFalse = 0x02;

  /// Signed 8-bit integer.
  static const int int8 = 0x03;

  /// Signed 16-bit integer.
  static const int int16 = 0x04;

  /// Signed 32-bit integer.
  static const int int32 = 0x05;

  /// Signed 64-bit integer.
  static const int int64 = 0x06;

  /// 32-bit IEEE 754 float.
  static const int float32 = 0x07;

  /// 64-bit IEEE 754 double.
  static const int float64 = 0x08;

  /// UTF-8 encoded String (uint32 length prefix).
  static const int string = 0x09;

  /// Raw byte array (uint32 length prefix).
  static const int bytes = 0x0A;

  /// List<dynamic> (uint32 element count prefix).
  static const int list = 0x0B;

  /// Map<dynamic, dynamic> (uint32 entry count prefix).
  static const int map = 0x0C;

  /// DateTime (int64 microsecondsSinceEpoch).
  static const int dateTime = 0x0D;

  /// Duration (int64 inMicroseconds).
  static const int duration = 0x0E;

  /// Set<dynamic> (uint32 element count prefix).
  static const int set_ = 0x0F;

  /// BigInt (length-prefixed decimal string encoding).
  static const int bigInt = 0x10;

  /// Uri (length-prefixed toString encoding).
  static const int uri = 0x11;

  /// Uint8List (optimised shortcut — uint32 length prefix).
  static const int uint8List = 0x12;

  /// Custom object — followed by 1-byte adapter typeId.
  static const int customObject = 0xF0;
}

// ─────────────────────────────────────────────────────────────────────────────
// SuperCodec
// ─────────────────────────────────────────────────────────────────────────────

/// The binary serialization engine of super_cache.
///
/// Converts any supported Dart value to a compact [Uint8List] and back.
///
/// **Supported built-in types:**
/// `null`, `bool`, `int` (stored in the smallest possible width), `double`,
/// `String`, `List`, `Map`, `Set`, `DateTime`, `Duration`, `Uint8List`,
/// `BigInt`, `Uri`.
///
/// **Custom types:** register a [SuperCacheAdapter] with [TypeRegistry] and
/// instances of that type will be serialized transparently.
///
/// Performance notes:
/// - Ints are encoded in the minimum width (1/2/4/8 bytes) to save space.
/// - Strings use a hand-rolled UTF-8 encoder with an ASCII fast-path.
/// - Codec instances are stateless and safe to reuse across calls.
final class SuperCodec {
  /// Creates a [SuperCodec] backed by the given [registry].
  ///
  /// Defaults to [TypeRegistry.instance] (the global singleton).
  SuperCodec({TypeRegistry? registry})
      : _registry = registry ?? TypeRegistry.instance;

  final TypeRegistry _registry;

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Encodes [value] to a compact binary representation.
  ///
  /// Throws [CacheCodecException] if the value's type has no adapter.
  Uint8List encode(dynamic value) {
    try {
      final writer = BinaryWriter(capacity: _estimateSize(value));
      _writeValue(writer, value);
      return writer.toBytes();
    } catch (e) {
      if (e is SuperCacheException) rethrow;
      throw CacheCodecException('Failed to encode value: $e', cause: e);
    }
  }

  /// Decodes a [Uint8List] previously produced by [encode].
  ///
  /// Throws [CacheCodecException] on malformed data.
  dynamic decode(Uint8List bytes) {
    try {
      final reader = BinaryReader(bytes);
      return _readValue(reader);
    } catch (e) {
      if (e is SuperCacheException) rethrow;
      throw CacheCodecException('Failed to decode bytes: $e', cause: e);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Write dispatch
  // ─────────────────────────────────────────────────────────────────────────

  void _writeValue(BinaryWriter w, dynamic value) {
    if (value == null) {
      w.writeByte(TypeIds.nullType);
      return;
    }
    if (value is bool) {
      w.writeByte(value ? TypeIds.boolTrue : TypeIds.boolFalse);
      return;
    }
    if (value is int) {
      _writeInt(w, value);
      return;
    }
    if (value is double) {
      // Store as float32 when precision is not lost, otherwise float64.
      final f32 = value.toDouble();
      if (f32.toDouble() == value &&
          !value.isNaN &&
          !value.isInfinite &&
          value.abs() < 3.4028235e38) {
        w.writeByte(TypeIds.float32);
        w.writeFloat32(value);
      } else {
        w.writeByte(TypeIds.float64);
        w.writeFloat64(value);
      }
      return;
    }
    if (value is String) {
      w.writeByte(TypeIds.string);
      w.writeString(value);
      return;
    }
    if (value is Uint8List) {
      // Specialised path for Uint8List — avoids boxing each byte as a List<int>
      w.writeByte(TypeIds.uint8List);
      w.writeLengthPrefixedBytes(value);
      return;
    }
    if (value is List) {
      w.writeByte(TypeIds.list);
      w.writeUint32(value.length);
      for (final item in value) {
        _writeValue(w, item);
      }
      return;
    }
    if (value is Set) {
      w.writeByte(TypeIds.set_);
      w.writeUint32(value.length);
      for (final item in value) {
        _writeValue(w, item);
      }
      return;
    }
    if (value is Map) {
      w.writeByte(TypeIds.map);
      w.writeUint32(value.length);
      for (final entry in value.entries) {
        _writeValue(w, entry.key);
        _writeValue(w, entry.value);
      }
      return;
    }
    if (value is DateTime) {
      w.writeByte(TypeIds.dateTime);
      w.writeInt64(value.microsecondsSinceEpoch);
      return;
    }
    if (value is Duration) {
      w.writeByte(TypeIds.duration);
      w.writeInt64(value.inMicroseconds);
      return;
    }
    if (value is BigInt) {
      w.writeByte(TypeIds.bigInt);
      w.writeString(value.toString());
      return;
    }
    if (value is Uri) {
      w.writeByte(TypeIds.uri);
      w.writeString(value.toString());
      return;
    }

    // ── Custom adapter path ──────────────────────────────────────────────────
    final adapter = _registry.findAdapterForValue(value);
    if (adapter != null) {
      w.writeByte(TypeIds.customObject);
      w.writeByte(adapter.typeId);
      adapter.write(w, value);
      return;
    }

    throw MissingAdapterException(value.runtimeType.toString());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Read dispatch
  // ─────────────────────────────────────────────────────────────────────────

  dynamic _readValue(BinaryReader r) {
    final typeId = r.readByte();

    switch (typeId) {
      case TypeIds.nullType:
        return null;
      case TypeIds.boolTrue:
        return true;
      case TypeIds.boolFalse:
        return false;
      case TypeIds.int8:
        return r.readInt8();
      case TypeIds.int16:
        return r.readInt16();
      case TypeIds.int32:
        return r.readInt32();
      case TypeIds.int64:
        return r.readInt64();
      case TypeIds.float32:
        return r.readFloat32();
      case TypeIds.float64:
        return r.readFloat64();
      case TypeIds.string:
        return r.readString();
      case TypeIds.uint8List:
        return r.readLengthPrefixedBytes();
      case TypeIds.bytes:
        return r.readLengthPrefixedBytes();
      case TypeIds.list:
        final length = r.readUint32();
        return List<dynamic>.generate(length, (_) => _readValue(r),
            growable: false);
      case TypeIds.set_:
        final length = r.readUint32();
        final result = <dynamic>{};
        for (var i = 0; i < length; i++) {
          result.add(_readValue(r));
        }
        return result;
      case TypeIds.map:
        final length = r.readUint32();
        final result = <dynamic, dynamic>{};
        for (var i = 0; i < length; i++) {
          final k = _readValue(r);
          final v = _readValue(r);
          result[k] = v;
        }
        return result;
      case TypeIds.dateTime:
        return DateTime.fromMicrosecondsSinceEpoch(r.readInt64());
      case TypeIds.duration:
        return Duration(microseconds: r.readInt64());
      case TypeIds.bigInt:
        return BigInt.parse(r.readString());
      case TypeIds.uri:
        return Uri.parse(r.readString());
      case TypeIds.customObject:
        final customTypeId = r.readByte();
        final adapter = _registry.findAdapterById(customTypeId);
        if (adapter == null) {
          throw CacheCodecException(
            'No adapter registered for typeId $customTypeId. '
            'Call SuperCache.registerAdapter() before reading this type.',
          );
        }
        return adapter.read(r);
      default:
        throw CacheCodecException(
          'Unknown typeId: 0x${typeId.toRadixString(16).padLeft(2, '0')}. '
          'The data may have been written by a newer version of super_cache.',
        );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Int width optimisation
  // ─────────────────────────────────────────────────────────────────────────

  void _writeInt(BinaryWriter w, int value) {
    if (value >= -128 && value <= 127) {
      w
        ..writeByte(TypeIds.int8)
        ..writeInt8(value);
    } else if (value >= -32768 && value <= 32767) {
      w
        ..writeByte(TypeIds.int16)
        ..writeInt16(value);
    } else if (value >= -2147483648 && value <= 2147483647) {
      w
        ..writeByte(TypeIds.int32)
        ..writeInt32(value);
    } else {
      w
        ..writeByte(TypeIds.int64)
        ..writeInt64(value);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Buffer size estimation (avoids excessive reallocation)
  // ─────────────────────────────────────────────────────────────────────────

  int _estimateSize(dynamic value) {
    if (value == null) return 1;
    if (value is bool) return 1;
    if (value is int) return 9; // type byte + up to 8 data bytes
    if (value is double) return 9;
    if (value is String) return 5 + value.length * 3; // type + len + UTF-8
    if (value is Uint8List) return 5 + value.length;
    if (value is List) return 5 + value.length * 16;
    if (value is Map) return 5 + value.length * 32;
    if (value is DateTime) return 9;
    if (value is Duration) return 9;
    return 64; // default for custom objects
  }
}
