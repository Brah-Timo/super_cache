import 'package:super_cache/src/codec/binary_reader.dart';
import 'package:super_cache/src/codec/binary_writer.dart';
import 'package:super_cache/src/codec/type_registry.dart';

/// Adapter for `List<String>` — typeId 204.
///
/// More compact than the generic List path because it skips per-element
/// type bytes (all elements are known to be strings).
final class StringListAdapter extends SuperCacheAdapter<List<String>> {
  /// Creates a [StringListAdapter].
  StringListAdapter();

  @override
  int get typeId => 204;

  @override
  List<String> read(BinaryReader reader) {
    final length = reader.readUint32();
    return List<String>.generate(length, (_) => reader.readString(),
        growable: false);
  }

  @override
  void write(BinaryWriter writer, List<String> obj) {
    writer.writeUint32(obj.length);
    for (final s in obj) {
      writer.writeString(s);
    }
  }
}

/// Adapter for `List<int>` — typeId 205.
///
/// Each element is stored as a full int64 for simplicity.
/// For large integer lists consider using Uint8List instead.
final class IntListAdapter extends SuperCacheAdapter<List<int>> {
  /// Creates an [IntListAdapter].
  IntListAdapter();

  @override
  int get typeId => 205;

  @override
  List<int> read(BinaryReader reader) {
    final length = reader.readUint32();
    return List<int>.generate(length, (_) => reader.readInt64(),
        growable: false);
  }

  @override
  void write(BinaryWriter writer, List<int> obj) {
    writer.writeUint32(obj.length);
    for (final i in obj) {
      writer.writeInt64(i);
    }
  }
}

/// Adapter for `List<double>` — typeId 206.
final class DoubleListAdapter extends SuperCacheAdapter<List<double>> {
  /// Creates a [DoubleListAdapter].
  DoubleListAdapter();

  @override
  int get typeId => 206;

  @override
  List<double> read(BinaryReader reader) {
    final length = reader.readUint32();
    return List<double>.generate(length, (_) => reader.readFloat64(),
        growable: false);
  }

  @override
  void write(BinaryWriter writer, List<double> obj) {
    writer.writeUint32(obj.length);
    for (final d in obj) {
      writer.writeFloat64(d);
    }
  }
}

/// Adapter for `List<bool>` — typeId 207.
///
/// Packs 8 bools per byte for maximum space efficiency.
final class BoolListAdapter extends SuperCacheAdapter<List<bool>> {
  /// Creates a [BoolListAdapter].
  BoolListAdapter();

  @override
  int get typeId => 207;

  @override
  List<bool> read(BinaryReader reader) {
    final length = reader.readUint32();
    if (length == 0) return const [];

    final byteCount = (length + 7) ~/ 8;
    final result = List<bool>.filled(length, false, growable: false);

    for (var byteIndex = 0; byteIndex < byteCount; byteIndex++) {
      final byte = reader.readByte();
      for (var bit = 0; bit < 8; bit++) {
        final index = byteIndex * 8 + bit;
        if (index >= length) break;
        result[index] = (byte >> bit) & 1 == 1;
      }
    }
    return result;
  }

  @override
  void write(BinaryWriter writer, List<bool> obj) {
    writer.writeUint32(obj.length);
    if (obj.isEmpty) return;

    final byteCount = (obj.length + 7) ~/ 8;
    for (var byteIndex = 0; byteIndex < byteCount; byteIndex++) {
      var byte = 0;
      for (var bit = 0; bit < 8; bit++) {
        final index = byteIndex * 8 + bit;
        if (index < obj.length && obj[index]) {
          byte |= 1 << bit;
        }
      }
      writer.writeByte(byte);
    }
  }
}
