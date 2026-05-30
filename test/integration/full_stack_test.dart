// test/integration/full_stack_test.dart
// ignore_for_file: avoid_print

import 'package:test/test.dart';
import 'package:super_cache/super_cache.dart';

void main() {
  group('SuperCache full-stack (memory-only)', () {
    late SuperCache cache;

    setUp(() async {
      await SuperCache.disposeAll();
      cache = await SuperCache.init(
        config: const CacheConfig(
          maxMemoryEntries: 200,
          enableDiskCache: false,
          enableStatistics: true,
          defaultTtl: Duration(hours: 1),
        ),
      );
    });

    tearDown(() async {
      await SuperCache.disposeAll();
    });

    // ── Basic read/write ──────────────────────────────────────────────────────

    test('put and get String', () async {
      await cache.put('greeting', 'Hello, World!');
      final result = await cache.get<String>('greeting');
      expect(result, equals('Hello, World!'));
    });

    test('put and get int', () async {
      await cache.put('count', 42);
      final result = await cache.get<int>('count');
      expect(result, equals(42));
    });

    test('put and get bool', () async {
      await cache.put('flag', false);
      final result = await cache.get<bool>('flag');
      expect(result, isFalse);
    });

    test('get returns null for missing key', () async {
      final result = await cache.get<String>('nonexistent');
      expect(result, isNull);
    });

    test('put overwrites existing value', () async {
      await cache.put('k', 'v1');
      await cache.put('k', 'v2');
      expect(await cache.get<String>('k'), equals('v2'));
    });

    // ── Delete ────────────────────────────────────────────────────────────────

    test('remove deletes key', () async {
      await cache.put('rm_key', 'value');
      final removed = await cache.remove('rm_key');
      expect(removed, isTrue);
      expect(await cache.get<String>('rm_key'), isNull);
    });

    test('remove returns false for missing key', () async {
      final removed = await cache.remove('does_not_exist');
      expect(removed, isFalse);
    });

    // ── containsKey ───────────────────────────────────────────────────────────

    test('containsKey returns true after put', () async {
      await cache.put('present', 1);
      expect(await cache.containsKey('present'), isTrue);
    });

    test('containsKey returns false for missing key', () async {
      expect(await cache.containsKey('absent'), isFalse);
    });

    // ── Batch operations ──────────────────────────────────────────────────────

    test('putAll and getAll', () async {
      await cache.putAll({
        'city:1': 'New York',
        'city:2': 'London',
        'city:3': 'Tokyo',
      });

      final results = await cache.getAll(['city:1', 'city:2', 'city:3']);
      expect(results['city:1'], equals('New York'));
      expect(results['city:2'], equals('London'));
      expect(results['city:3'], equals('Tokyo'));
    });

    test('removeAll deletes multiple keys', () async {
      await cache.putAll({'a': 1, 'b': 2, 'c': 3});
      await cache.removeAll(['a', 'b']);
      expect(await cache.containsKey('a'), isFalse);
      expect(await cache.containsKey('b'), isFalse);
      expect(await cache.containsKey('c'), isTrue);
    });

    // ── TTL ───────────────────────────────────────────────────────────────────

    test('entry expires after TTL', () async {
      await cache.put(
        'ttl_key',
        'temp_value',
        ttl: const Duration(milliseconds: 100),
      );

      expect(await cache.get<String>('ttl_key'), equals('temp_value'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await cache.get<String>('ttl_key'), isNull);
    });

    // ── Cache-aside ───────────────────────────────────────────────────────────

    test('getOrPut returns cached value on second call', () async {
      var loaderCalls = 0;

      Future<String> loader() async {
        loaderCalls++;
        return 'loaded_value';
      }

      final first = await cache.getOrPut('lazy', loader);
      final second = await cache.getOrPut('lazy', loader);

      expect(first, equals('loaded_value'));
      expect(second, equals('loaded_value'));
      expect(loaderCalls, equals(1));
    });

    // ── Statistics ────────────────────────────────────────────────────────────

    test('statistics record hits and misses', () async {
      await cache.put('stat_key', 'value');
      await cache.get<String>('stat_key');       // L1 hit
      await cache.get<String>('missing_key');    // miss

      final snap = cache.statistics.snapshot();
      expect(snap.l1Hits, greaterThanOrEqualTo(1));
      expect(snap.misses, greaterThanOrEqualTo(1));
      expect(snap.writes, greaterThanOrEqualTo(1));
    });

    test('statistics hitRate is between 0 and 1', () async {
      await cache.put('k', 'v');
      await cache.get<String>('k');

      final snap = cache.statistics.snapshot();
      expect(snap.hitRate, inInclusiveRange(0.0, 1.0));
    });

    // ── Clear ────────────────────────────────────────────────────────────────

    test('clear empties the cache', () async {
      await cache.put('x', 1);
      await cache.put('y', 2);
      await cache.clear();

      expect(await cache.containsKey('x'), isFalse);
      expect(await cache.containsKey('y'), isFalse);
    });

    // ── getAllKeys ────────────────────────────────────────────────────────────

    test('getAllKeys returns all inserted keys', () async {
      await cache.put('kk1', 'v');
      await cache.put('kk2', 'v');
      final keys = await cache.getAllKeys();
      expect(keys, containsAll(['kk1', 'kk2']));
    });
  });
}
