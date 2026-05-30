import 'package:super_cache/src/codec/binary_reader.dart';
import 'package:super_cache/src/codec/binary_writer.dart';
import 'package:super_cache/src/codec/type_registry.dart';

/// Adapter for nullable [String] — typeId 200.
///
/// Stores a presence flag (1 byte) followed by the string bytes when present.
///
/// This adapter is pre-registered automatically; you do not need to register it.
final class NullableStringAdapter extends SuperCacheAdapter<String?> {
  /// Creates a [NullableStringAdapter].
  NullableStringAdapter();

  @override
  int get typeId => 200;

  @override
  String? read(BinaryReader reader) {
    final present = reader.readBool();
    if (!present) return null;
    return reader.readString();
  }

  @override
  void write(BinaryWriter writer, String? obj) {
    writer.writeBool(obj != null);
    if (obj != null) writer.writeString(obj);
  }
}

/// Adapter for nullable [int] — typeId 201.
final class NullableIntAdapter extends SuperCacheAdapter<int?> {
  /// Creates a [NullableIntAdapter].
  NullableIntAdapter();

  @override
  int get typeId => 201;

  @override
  int? read(BinaryReader reader) {
    final present = reader.readBool();
    if (!present) return null;
    return reader.readInt64();
  }

  @override
  void write(BinaryWriter writer, int? obj) {
    writer.writeBool(obj != null);
    if (obj != null) writer.writeInt64(obj);
  }
}

/// Adapter for nullable [double] — typeId 202.
final class NullableDoubleAdapter extends SuperCacheAdapter<double?> {
  /// Creates a [NullableDoubleAdapter].
  NullableDoubleAdapter();

  @override
  int get typeId => 202;

  @override
  double? read(BinaryReader reader) {
    final present = reader.readBool();
    if (!present) return null;
    return reader.readFloat64();
  }

  @override
  void write(BinaryWriter writer, double? obj) {
    writer.writeBool(obj != null);
    if (obj != null) writer.writeFloat64(obj);
  }
}

/// Adapter for nullable [bool] — typeId 203.
final class NullableBoolAdapter extends SuperCacheAdapter<bool?> {
  /// Creates a [NullableBoolAdapter].
  NullableBoolAdapter();

  @override
  int get typeId => 203;

  @override
  bool? read(BinaryReader reader) {
    final present = reader.readBool();
    if (!present) return null;
    return reader.readBool();
  }

  @override
  void write(BinaryWriter writer, bool? obj) {
    writer.writeBool(obj != null);
    if (obj != null) writer.writeBool(obj);
  }
}
