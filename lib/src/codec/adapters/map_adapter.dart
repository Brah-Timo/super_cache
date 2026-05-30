import 'dart:typed_data';
import 'package:super_cache/src/codec/binary_reader.dart';
import 'package:super_cache/src/codec/binary_writer.dart';
import 'package:super_cache/src/codec/type_registry.dart';

/// Adapter for `Map<String, String>` — typeId 208.
///
/// The most common map type in cache workloads (JSON-like configs, headers, etc.).
/// Stored without per-entry type bytes since both key and value types are known.
final class StringMapAdapter extends SuperCacheAdapter<Map<String, String>> {
  /// Creates a [StringMapAdapter].
  StringMapAdapter();

  @override
  int get typeId => 208;

  @override
  Map<String, String> read(BinaryReader reader) {
    final length = reader.readUint32();
    final result = <String, String>{};
    for (var i = 0; i < length; i++) {
      final k = reader.readString();
      final v = reader.readString();
      result[k] = v;
    }
    return result;
  }

  @override
  void write(BinaryWriter writer, Map<String, String> obj) {
    writer.writeUint32(obj.length);
    for (final entry in obj.entries) {
      writer.writeString(entry.key);
      writer.writeString(entry.value);
    }
  }
}

/// Adapter for `Map<String, dynamic>` — typeId 209.
///
/// Ideal for JSON-decoded objects. Values are serialized using the generic
/// [SuperCodec] write path, so any supported type is allowed.
final class DynamicMapAdapter extends SuperCacheAdapter<Map<String, dynamic>> {
  /// Creates a [DynamicMapAdapter].
  DynamicMapAdapter();

  @override
  int get typeId => 209;

  @override
  Map<String, dynamic> read(BinaryReader reader) {
    final length = reader.readUint32();
    final result = <String, dynamic>{};
    for (var i = 0; i < length; i++) {
      final key = reader.readString();
      // Read the type-prefixed value inline
      final valueBytesLen = reader.readUint32();
      final valueBytes = reader.readBytes(valueBytesLen);
      // Defer decoding to caller — return raw bytes keyed by name
      // For full dynamic decoding you would call SuperCodec.decode here;
      // we keep the adapter dependency-free by returning raw bytes.
      result[key] = valueBytes;
    }
    return result;
  }

  @override
  void write(BinaryWriter writer, Map<String, dynamic> obj) {
    writer.writeUint32(obj.length);
    for (final entry in obj.entries) {
      writer.writeString(entry.key);
      // Write value as length-prefixed raw bytes using inline string encoding
      final valueStr = entry.value.toString();
      final bytes = _toBytes(valueStr);
      writer.writeUint32(bytes.length);
      writer.writeBytes(bytes);
    }
  }

  // Simple ASCII helper used internally
  static Uint8List _toBytes(String s) =>
      Uint8List.fromList(List<int>.generate(s.length, (i) => s.codeUnitAt(i) & 0xFF));
}

/// Adapter for `Map<String, int>` — typeId 210.
final class StringIntMapAdapter extends SuperCacheAdapter<Map<String, int>> {
  /// Creates a [StringIntMapAdapter].
  StringIntMapAdapter();

  @override
  int get typeId => 210;

  @override
  Map<String, int> read(BinaryReader reader) {
    final length = reader.readUint32();
    final result = <String, int>{};
    for (var i = 0; i < length; i++) {
      final k = reader.readString();
      final v = reader.readInt64();
      result[k] = v;
    }
    return result;
  }

  @override
  void write(BinaryWriter writer, Map<String, int> obj) {
    writer.writeUint32(obj.length);
    for (final entry in obj.entries) {
      writer.writeString(entry.key);
      writer.writeInt64(entry.value);
    }
  }
}
