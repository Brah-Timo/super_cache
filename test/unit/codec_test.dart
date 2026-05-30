// test/unit/codec_test.dart
// ignore_for_file: avoid_print

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:super_cache/super_cache.dart';
import 'package:super_cache/src/codec/super_codec.dart' show SuperCodec;

void main() {
  group('TypeRegistry', () {
    late TypeRegistry registry;

    setUp(() {
      registry = TypeRegistry.instance;
      registry.clear();
    });

    tearDown(() {
      registry.clear();
    });

    test('register and lookup by typeId', () {
      final adapter = _StringAdapter();
      registry.register(adapter);
      expect(registry.findAdapterById(1), same(adapter));
    });

    test('register and lookup by type', () {
      final adapter = _StringAdapter();
      registry.register(adapter);
      expect(registry.findAdapterForType(String), same(adapter));
    });

    test('count returns registered count', () {
      expect(registry.count, 0);
      registry.register(_StringAdapter());
      expect(registry.count, 1);
    });

    test('unregister removes adapter', () {
      registry.register(_StringAdapter());
      expect(registry.unregister(1), isTrue);
      expect(registry.findAdapterById(1), isNull);
    });

    test('hasAdapter returns true when registered', () {
      registry.register(_StringAdapter());
      expect(registry.hasAdapter(1), isTrue);
    });

    test('hasAdapter returns false when not registered', () {
      expect(registry.hasAdapter(99), isFalse);
    });

    test('throws on duplicate typeId with different adapter', () {
      registry.register(_StringAdapter());
      expect(
        () => registry.register(_StringAdapter2()),
        throwsA(isA<AdapterConflictException>()),
      );
    });

    test('registeredTypes lists adapter info', () {
      registry.register(_StringAdapter());
      final types = registry.registeredTypes;
      expect(types.length, 1);
      expect(types.first, contains('[1]'));
    });

    test('clear empties registry', () {
      registry.register(_StringAdapter());
      registry.clear();
      expect(registry.count, 0);
    });

    test('throws on typeId > 220', () {
      expect(
        () => registry.register(_InvalidAdapter()),
        throwsA(isA<InvalidConfigException>()),
      );
    });
  });

  group('SuperCodec round-trips', () {
    late SuperCodec codec;

    setUp(() {
      TypeRegistry.instance.clear();
      codec = SuperCodec(registry: TypeRegistry.instance);
    });

    tearDown(() {
      TypeRegistry.instance.clear();
    });

    test('encodes and decodes String', () {
      TypeRegistry.instance.register(NullableStringAdapter());
      final encoded = codec.encode('hello world');
      final decoded = codec.decode(encoded);
      expect(decoded, equals('hello world'));
    });

    test('encodes and decodes int', () {
      TypeRegistry.instance.register(NullableIntAdapter());
      final encoded = codec.encode(42);
      final decoded = codec.decode(encoded);
      expect(decoded, equals(42));
    });

    test('encodes and decodes bool', () {
      TypeRegistry.instance.register(NullableBoolAdapter());
      final encoded = codec.encode(true);
      final decoded = codec.decode(encoded);
      expect(decoded, equals(true));
    });

    test('encodes and decodes double', () {
      TypeRegistry.instance.register(NullableDoubleAdapter());
      final encoded = codec.encode(3.14);
      final decoded = codec.decode(encoded);
      expect((decoded as double).toStringAsFixed(2), equals('3.14'));
    });

    test('encode returns Uint8List', () {
      TypeRegistry.instance.register(NullableStringAdapter());
      final result = codec.encode('test');
      expect(result, isA<Uint8List>());
    });
  });

  group('BinaryReader / BinaryWriter', () {
    test('write and read uint32', () {
      final writer = BinaryWriter();
      writer.writeUint32(12345678);
      final bytes = writer.toBytes();
      final reader = BinaryReader(bytes);
      expect(reader.readUint32(), equals(12345678));
    });

    test('write and read int64', () {
      final writer = BinaryWriter();
      writer.writeInt64(-9876543210);
      final bytes = writer.toBytes();
      final reader = BinaryReader(bytes);
      expect(reader.readInt64(), equals(-9876543210));
    });

    test('write and read bool', () {
      final writer = BinaryWriter();
      writer.writeBool(true);
      writer.writeBool(false);
      final bytes = writer.toBytes();
      final reader = BinaryReader(bytes);
      expect(reader.readBool(), isTrue);
      expect(reader.readBool(), isFalse);
    });

    test('write and read string', () {
      final writer = BinaryWriter();
      writer.writeString('Hello, 世界');
      final bytes = writer.toBytes();
      final reader = BinaryReader(bytes);
      expect(reader.readString(), equals('Hello, 世界'));
    });

    test('write and read float64', () {
      final writer = BinaryWriter();
      writer.writeFloat64(2.718281828);
      final bytes = writer.toBytes();
      final reader = BinaryReader(bytes);
      expect(reader.readFloat64(), closeTo(2.718281828, 1e-9));
    });

    test('reader remaining decreases after reads', () {
      final writer = BinaryWriter();
      writer.writeUint32(1);
      writer.writeUint32(2);
      final bytes = writer.toBytes();
      final reader = BinaryReader(bytes);
      expect(reader.remaining, equals(8));
      reader.readUint32();
      expect(reader.remaining, equals(4));
    });

    test('throws RangeError on over-read', () {
      final writer = BinaryWriter();
      writer.writeByte(0xFF);
      final bytes = writer.toBytes();
      final reader = BinaryReader(bytes);
      reader.readByte();
      expect(() => reader.readByte(), throwsRangeError);
    });
  });
}

// ─── Test adapters ────────────────────────────────────────────────────────────

class _StringAdapter extends SuperCacheAdapter<String> {
  @override
  int get typeId => 1;

  @override
  String read(BinaryReader reader) => reader.readString();

  @override
  void write(BinaryWriter writer, String obj) => writer.writeString(obj);
}

class _StringAdapter2 extends SuperCacheAdapter<String> {
  @override
  int get typeId => 1; // same typeId as _StringAdapter — triggers conflict

  @override
  String read(BinaryReader reader) => reader.readString();

  @override
  void write(BinaryWriter writer, String obj) => writer.writeString(obj);
}

class _InvalidAdapter extends SuperCacheAdapter<int> {
  @override
  int get typeId => 300; // > 220

  @override
  int read(BinaryReader reader) => reader.readInt32();

  @override
  void write(BinaryWriter writer, int obj) => writer.writeInt32(obj);
}

// Re-export built-in adapters for use in tests
class NullableStringAdapter extends SuperCacheAdapter<String?> {
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

class NullableIntAdapter extends SuperCacheAdapter<int?> {
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

class NullableBoolAdapter extends SuperCacheAdapter<bool?> {
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

class NullableDoubleAdapter extends SuperCacheAdapter<double?> {
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
