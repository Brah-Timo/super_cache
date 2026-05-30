import 'package:test/test.dart';
import 'package:super_cache/src/core/cache_config.dart';
import 'package:super_cache/src/engine/l1_memory_cache.dart';
import 'package:super_cache/src/eviction/arc_policy.dart';
import 'package:super_cache/src/eviction/lru_policy.dart';

void main() {
  group('L1MemoryCache — basic operations', () {
    late L1MemoryCache cache;

    setUp(() {
      cache = L1MemoryCache(
        config: const CacheConfig(maxMemoryEntries: 100),
        evictionPolicy: LruPolicy(maxSize: 100),
      );
    });

    test('put and get string', () {
      cache.put('name', 'Alice', 5 * 2); // 10 bytes
      expect(cache.get<String>('name'), equals('Alice'));
    });

    test('get returns null for missing key', () {
      expect(cache.get<String>('missing'), isNull);
    });

    test('put overwrites existing key', () {
      cache.put('k', 'v1', 2);
      cache.put('k', 'v2', 2);
      expect(cache.get<String>('k'), equals('v2'));
    });

    test('remove existing key returns true', () {
      cache.put('x', 42, 8);
      expect(cache.remove('x'), isTrue);
      expect(cache.get<int>('x'), isNull);
    });

    test('remove non-existent key returns false', () {
      expect(cache.remove('ghost'), isFalse);
    });

    test('containsKey returns false for missing key', () {
      expect(cache.containsKey('nope'), isFalse);
    });

    test('containsKey returns true for present key', () {
      cache.put('here', true, 4);
      expect(cache.containsKey('here'), isTrue);
    });

    test('length tracks live entries', () {
      cache.put('a', 1, 8);
      cache.put('b', 2, 8);
      expect(cache.length, equals(2));
      cache.remove('a');
      expect(cache.length, equals(1));
    });

    test('currentMemoryBytes accumulates correctly', () {
      cache.put('big', 'x' * 100, 200);
      expect(cache.currentMemoryBytes, equals(200));
      cache.remove('big');
      expect(cache.currentMemoryBytes, equals(0));
    });

    test('clear resets everything', () {
      cache.put('p', 1, 8);
      cache.put('q', 2, 8);
      cache.clear();
      expect(cache.length, equals(0));
      expect(cache.currentMemoryBytes, equals(0));
      expect(cache.hits, equals(0));
    });

    test('hit rate calculation', () {
      cache.put('h', 'hello', 10);
      cache.get<String>('h'); // hit
      cache.get<String>('missing'); // miss
      expect(cache.hitRate, closeTo(0.5, 0.01));
    });
  });

  group('L1MemoryCache — TTL', () {
    test('expired entry returns null and increments ttlExpiries', () async {
      final c = L1MemoryCache(
        config: const CacheConfig(),
        evictionPolicy: LruPolicy(),
      );
      c.put('ephemeral', 'value', 10,
          ttl: const Duration(milliseconds: 50));

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(c.get<String>('ephemeral'), isNull);
      expect(c.ttlExpiries, greaterThan(0));
    });

    test('non-expired entry survives TTL check', () async {
      final c = L1MemoryCache(
        config: const CacheConfig(),
        evictionPolicy: LruPolicy(),
      );
      c.put('durable', 'ok', 10,
          ttl: const Duration(seconds: 60));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.get<String>('durable'), equals('ok'));
    });

    test('clearExpired removes only expired entries', () async {
      final c = L1MemoryCache(
        config: const CacheConfig(),
        evictionPolicy: LruPolicy(),
      );
      c.put('short', 1, 8, ttl: const Duration(milliseconds: 50));
      c.put('long', 2, 8, ttl: const Duration(hours: 1));

      await Future<void>.delayed(const Duration(milliseconds: 80));
      final removed = c.clearExpired();

      expect(removed, equals(1));
      expect(c.get<int>('long'), equals(2));
    });
  });

  group('L1MemoryCache — eviction', () {
    test('evicts when maxMemoryEntries exceeded', () {
      final c = L1MemoryCache(
        config: const CacheConfig(maxMemoryEntries: 3),
        evictionPolicy: ArcPolicy(maxSize: 3),
      );
      c.put('a', 1, 8);
      c.put('b', 2, 8);
      c.put('c', 3, 8);
      c.put('d', 4, 8); // should evict one of a/b/c

      expect(c.length, equals(3));
      expect(c.evictions, equals(1));
    });

    test('evicts when maxMemorySizeBytes exceeded', () {
      final c = L1MemoryCache(
        config: const CacheConfig(
          maxMemoryEntries: 1000,
          maxMemorySizeBytes: 30, // tiny budget
        ),
        evictionPolicy: LruPolicy(maxSize: 1000),
      );
      c.put('big1', 'x' * 10, 10);
      c.put('big2', 'x' * 10, 10);
      c.put('big3', 'x' * 10, 10); // forces eviction
      c.put('big4', 'x' * 10, 10);

      expect(c.currentMemoryBytes, lessThanOrEqualTo(30));
    });
  });
}
