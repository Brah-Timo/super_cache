/// Marks a class as serializable by super_cache's code generator.
///
/// When applied to a class, the build_runner code generator will produce a
/// `<ClassName>Adapter` in a companion `.g.dart` file.
///
/// **Example:**
/// ```dart
/// part 'product.g.dart';
///
/// @Cacheable(typeId: 5)
/// class Product {
///   @CacheField(0) final String id;
///   @CacheField(1) final String name;
///   @CacheField(2) final double price;
///   @CacheField(3) final DateTime createdAt;
///
///   const Product({
///     required this.id,
///     required this.name,
///     required this.price,
///     required this.createdAt,
///   });
/// }
/// ```
///
/// Then register the adapter once at startup:
/// ```dart
/// SuperCache.registerAdapter(ProductAdapter());
/// await SuperCache.init();
/// ```
class Cacheable {
  /// Creates a [Cacheable] annotation.
  ///
  /// [typeId] must be unique within your application (0–220).
  const Cacheable({required this.typeId});

  /// Unique numeric identifier for this type in binary streams.
  ///
  /// Must be an integer between 0 and 220 (inclusive).
  /// **Never change a typeId** once data has been persisted with it — doing
  /// so will cause deserialization failures for existing cached data.
  final int typeId;
}

/// Marks a field in a [@Cacheable] class for inclusion in the generated adapter.
///
/// Fields without this annotation are ignored by the code generator.
///
/// [index] must be a non-negative integer unique within the class.
/// **Never change a field index** once data has been written — reorder the
/// annotation index instead of the physical field order if needed.
class CacheField {
  /// Creates a [CacheField] annotation.
  ///
  /// [index] — the ordinal position of this field in the binary representation.
  const CacheField(this.index);

  /// Ordinal position of this field (0-based, unique within the class).
  final int index;
}

/// Optional annotation to mark a field as the primary key.
///
/// When applied to a [String] field, the code generator will use its value
/// as the cache key instead of requiring the caller to specify a key manually.
class CacheKey {
  /// Creates a [CacheKey] annotation.
  const CacheKey();
}
