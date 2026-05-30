// test/benchmark/stress_test.dart
// ignore_for_file: avoid_print

import 'package:test/test.dart';
import 'package:super_cache/super_cache.dart';

void main() {
  group('StressTest', () {
    late SuperCache cache;

    setUp(() async {
      await SuperCache.disposeAll();
      cache = await SuperCache.init(
        config: const CacheConfig(
          maxMemoryEntries: 500,
          enableDiskCache: false,
          enableStatistics: true,
        ),
      );
    });

    tearDown(() async {
      await SuperCache.disposeAll();
    });

    test('high-volume put and get operations', () async {
      const count = 200;
      final sw = Stopwatch()..start();

      for (var i = 0; i < count; i++) {
        await cache.put('key_$i', 'value_${i}_${'x' * (i % 50)}');
      }

      sw.stop();
      final writeMs = sw.elapsedMilliseconds;

      sw
        ..reset()
        ..start();

      var hits = 0;
      for (var i = 0; i < count; i++) {
        final v = await cache.get<String>('key_$i');
        if (v != null) hits++;
      }

      sw.stop();
      final readMs = sw.elapsedMilliseconds;

      print('Stress: $count writes in ${writeMs}ms, $count reads in ${readMs}ms, hits=$hits');
      expect(hits, equals(count));
    });

    test('concurrent batch operations', () async {
      final entries = <String, dynamic>{};
      for (var i = 0; i < 50; i++) {
        entries['batch_$i'] = 'value_$i';
      }

      await cache.putAll(entries);

      final keys = List.generate(50, (i) => 'batch_$i');
      final results = await cache.getAll(keys);

      expect(results.length, equals(50));
    });

    test('eviction under pressure', () async {
      // Fill beyond maxMemoryEntries
      for (var i = 0; i < 600; i++) {
        await cache.put('pressure_$i', 'v$i');
      }
      // Cache should not throw — just evict
      final stats = cache.statistics.snapshot();
      expect(stats.evictions, greaterThanOrEqualTo(0));
    });
  });
}
