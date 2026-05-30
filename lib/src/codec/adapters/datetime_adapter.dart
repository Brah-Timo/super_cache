import 'package:super_cache/src/codec/binary_reader.dart';
import 'package:super_cache/src/codec/binary_writer.dart';
import 'package:super_cache/src/codec/type_registry.dart';

/// Adapter for [DateTime] — typeId 211.
///
/// Stores the value as a signed 64-bit microseconds-since-epoch integer plus
/// a UTC flag byte, preserving both UTC and local DateTimes exactly.
final class DateTimeAdapter extends SuperCacheAdapter<DateTime> {
  /// Creates a [DateTimeAdapter].
  DateTimeAdapter();

  @override
  int get typeId => 211;

  @override
  DateTime read(BinaryReader reader) {
    final us = reader.readInt64();
    final isUtc = reader.readBool();
    return isUtc
        ? DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true)
        : DateTime.fromMicrosecondsSinceEpoch(us);
  }

  @override
  void write(BinaryWriter writer, DateTime obj) {
    writer.writeInt64(obj.microsecondsSinceEpoch);
    writer.writeBool(obj.isUtc);
  }
}

/// Adapter for [Duration] — typeId 212.
///
/// Stored as a signed 64-bit integer of microseconds.
final class DurationAdapter extends SuperCacheAdapter<Duration> {
  /// Creates a [DurationAdapter].
  DurationAdapter();

  @override
  int get typeId => 212;

  @override
  Duration read(BinaryReader reader) =>
      Duration(microseconds: reader.readInt64());

  @override
  void write(BinaryWriter writer, Duration obj) =>
      writer.writeInt64(obj.inMicroseconds);
}

/// Adapter for [Uri] — typeId 213.
///
/// Stored as a UTF-8 string of the full URI representation.
final class UriAdapter extends SuperCacheAdapter<Uri> {
  /// Creates a [UriAdapter].
  UriAdapter();

  @override
  int get typeId => 213;

  @override
  Uri read(BinaryReader reader) => Uri.parse(reader.readString());

  @override
  void write(BinaryWriter writer, Uri obj) => writer.writeString(obj.toString());
}

/// Adapter for [BigInt] — typeId 214.
///
/// Stored as its decimal string representation. For very large integers
/// consider a more compact binary encoding — this adapter favours simplicity.
final class BigIntAdapter extends SuperCacheAdapter<BigInt> {
  /// Creates a [BigIntAdapter].
  BigIntAdapter();

  @override
  int get typeId => 214;

  @override
  BigInt read(BinaryReader reader) => BigInt.parse(reader.readString());

  @override
  void write(BinaryWriter writer, BigInt obj) =>
      writer.writeString(obj.toString());
}

/// Adapter for `List<DateTime>` — typeId 215.
final class DateTimeListAdapter extends SuperCacheAdapter<List<DateTime>> {
  /// Creates a [DateTimeListAdapter].
  DateTimeListAdapter();

  @override
  int get typeId => 215;

  final _adapter = DateTimeAdapter();

  @override
  List<DateTime> read(BinaryReader reader) {
    final length = reader.readUint32();
    return List<DateTime>.generate(length, (_) => _adapter.read(reader),
        growable: false);
  }

  @override
  void write(BinaryWriter writer, List<DateTime> obj) {
    writer.writeUint32(obj.length);
    for (final dt in obj) {
      _adapter.write(writer, dt);
    }
  }
}
