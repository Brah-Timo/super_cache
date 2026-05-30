/// Abstract interface for L1 cache eviction policies.
///
/// An eviction policy tracks the "value" of each key in the cache
/// (where value is defined differently per algorithm) and nominates
/// the least valuable key for removal when the cache is full.
///
/// Implementations must be **O(log n)** or better for all operations
/// to avoid becoming the bottleneck in the hot read/write path.
///
/// All methods are synchronous — eviction decisions must be instant.
abstract interface class EvictionPolicy {
  /// Called when a brand-new [key] is inserted into the cache.
  void onInsert(String key);

  /// Called every time an existing [key] is read (cache hit).
  void onAccess(String key);

  /// Called when an existing [key]'s value is overwritten.
  void onUpdate(String key);

  /// Called when [key] is removed (manual delete, TTL expiry, or eviction).
  void onRemove(String key);

  /// Nominates one key from [availableKeys] for eviction.
  ///
  /// Returns `null` if [availableKeys] is empty.
  ///
  /// The nominated key must exist in [availableKeys]; the caller is
  /// responsible for the actual removal from the cache map.
  String? selectForEviction(List<String> availableKeys);

  /// Resets all internal tracking state.
  ///
  /// Called when the cache is cleared.
  void clear();

  /// Returns a debug-friendly map of internal state (for diagnostics only).
  Map<String, dynamic> get debugInfo;
}
