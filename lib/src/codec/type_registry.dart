import 'package:super_cache/src/codec/binary_reader.dart';
import 'package:super_cache/src/codec/binary_writer.dart';
import 'package:super_cache/src/core/cache_exceptions.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Abstract Adapter
// ─────────────────────────────────────────────────────────────────────────────

/// Defines how a custom Dart type is serialized to and from bytes.
///
/// Extend this class and register your adapter with
/// [SuperCache.registerAdapter] before reading or writing objects of type [T].
///
/// **Type IDs:** Choose a `typeId` between 0 and 220 that is unique within
/// your project. Type IDs 221–255 are reserved by super_cache.
///
/// ```dart
/// class UserAdapter extends SuperCacheAdapter<User> {
///   @override
///   int get typeId => 1;
///
///   @override
///   User read(BinaryReader reader) {
///     return User(
///       id:   reader.readString(),
///       name: reader.readString(),
///       age:  reader.readInt32(),
///     );
///   }
///
///   @override
///   void write(BinaryWriter writer, User obj) {
///     writer.writeString(obj.id);
///     writer.writeString(obj.name);
///     writer.writeInt32(obj.age);
///   }
/// }
/// ```
abstract class SuperCacheAdapter<T> {
  /// A unique non-negative integer that identifies this type in binary streams.
  ///
  /// Must be between 0 and 220 (inclusive). Must not change across app versions
  /// unless you also migrate all existing cached data.
  int get typeId;

  /// Deserializes an object of type [T] from [reader].
  ///
  /// Must read bytes in exactly the same order as [write] writes them.
  T read(BinaryReader reader);

  /// Serializes [obj] into [writer].
  ///
  /// Must write bytes in exactly the same order as [read] reads them.
  void write(BinaryWriter writer, T obj);

  /// The Dart runtime type this adapter handles.
  Type get adaptedType => T;
}

// ─────────────────────────────────────────────────────────────────────────────
// Type Registry (singleton)
// ─────────────────────────────────────────────────────────────────────────────

/// A global registry mapping type IDs and Dart [Type]s to [SuperCacheAdapter]s.
///
/// This class is a singleton — access it via [TypeRegistry.instance].
///
/// Users interact with it indirectly through [SuperCache.registerAdapter].
final class TypeRegistry {
  TypeRegistry._();

  /// The single global instance.
  static final TypeRegistry instance = TypeRegistry._();

  /// Internal type-ID → adapter map.
  final Map<int, SuperCacheAdapter<dynamic>> _byId = {};

  /// Internal Dart Type → adapter map.
  final Map<Type, SuperCacheAdapter<dynamic>> _byType = {};

  // ─────────────────────────────────────────────────────────────────────────
  // Registration
  // ─────────────────────────────────────────────────────────────────────────

  /// Registers [adapter] with the registry.
  ///
  /// Throws [AdapterConflictException] if the [adapter]'s [typeId] is already
  /// taken by a different adapter.
  void register<T>(SuperCacheAdapter<T> adapter) {
    if (adapter.typeId < 0 || adapter.typeId > 220) {
      throw InvalidConfigException(
        'Adapter typeId must be between 0 and 220. '
        'Got ${adapter.typeId} for type ${adapter.adaptedType}.',
      );
    }

    final existing = _byId[adapter.typeId];
    if (existing != null && existing.runtimeType != adapter.runtimeType) {
      throw AdapterConflictException(
        adapter.typeId,
        existing.adaptedType.toString(),
        adapter.adaptedType.toString(),
      );
    }

    _byId[adapter.typeId] = adapter;
    _byType[adapter.adaptedType] = adapter;
  }

  /// Removes the adapter with [typeId] from the registry.
  ///
  /// Returns `true` if an adapter was removed.
  bool unregister(int typeId) {
    final adapter = _byId.remove(typeId);
    if (adapter == null) return false;
    _byType.remove(adapter.adaptedType);
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lookup
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the adapter for the given [typeId], or `null` if none is registered.
  SuperCacheAdapter<dynamic>? findAdapterById(int typeId) => _byId[typeId];

  /// Returns the adapter that handles the runtime type of [value], or `null`.
  SuperCacheAdapter<dynamic>? findAdapterForValue(dynamic value) {
    return _byType[value.runtimeType];
  }

  /// Returns the adapter for the given Dart [type], or `null`.
  SuperCacheAdapter<dynamic>? findAdapterForType(Type type) => _byType[type];

  /// Whether any adapter is registered for [typeId].
  bool hasAdapter(int typeId) => _byId.containsKey(typeId);

  /// The total number of registered adapters.
  int get count => _byId.length;

  /// Clears all registered adapters.
  ///
  /// ⚠️ Intended for testing only — do not call in production code.
  void clear() {
    _byId.clear();
    _byType.clear();
  }

  /// Returns a debug list of all registered adapters.
  List<String> get registeredTypes =>
      _byId.entries.map((e) => '[${e.key}] ${e.value.adaptedType}').toList();

  @override
  String toString() => 'TypeRegistry(${_byId.length} adapters: '
      '${_byId.keys.join(', ')})';
}
