import 'package:test/test.dart';
import 'package:super_cache/src/core/cache_entry.dart';
import 'package:super_cache/src/eviction/ttl_manager.dart';

void main() {
  group('CacheEntry — TTL', () {
    test('isExpired is false when ttl is null', () {
      final entry = CacheEntry<String>(
        key: 'k',
        value: 'v',
        sizeBytes: 2,
      );
      expect(entry.isExpired, isFalse);
      expect(entry.expiresAt, isNull);
      expect(entry.remainingTtl, isNull);
    });

    test('isExpired is false before TTL elapses', () {
      final entry = CacheEntry<int>(
        key: 'k',
        value: 42,
        sizeBytes: 8,
        ttl: const Duration(hours: 1),
      );
      expect(entry.isExpired, isFalse);
      expect(entry.remainingTtl!.inSeconds, greaterThan(3500));
    });

    test('isExpired is true after TTL elapses', () async {
      final entry = CacheEntry<String>(
        key: 'short',
        value: 'bye',
        sizeBytes: 6,
        ttl: const Duration(milliseconds: 50),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(entry.isExpired, isTrue);
      expect(entry.remainingTtl, equals(Duration.zero));
    });

    test('expiresAt is approximately now + ttl', () {
      const ttl = Duration(minutes: 10);
      final entry = CacheEntry<bool>(
        key: 'e',
        value: true,
        sizeBytes: 1,
        ttl: ttl,
      );
      final expectedExpiry = DateTime.now().add(ttl);
      expect(
        entry.expiresAt!.difference(expectedExpiry).abs().inSeconds,
        lessThan(2),
      );
    });
  });

  group('CacheEntry — metadata', () {
    test('recordAccess increments accessCount', () {
      final entry = CacheEntry<int>(key: 'k', value: 1, sizeBytes: 8);
      expect(entry.accessCount, equals(0));
      entry.recordAccess();
      entry.recordAccess();
      expect(entry.accessCount, equals(2));
    });

    test('updateValue increments version and writeCount', () {
      final entry = CacheEntry<String>(key: 'k', value: 'v1', sizeBytes: 2);
      expect(entry.version, equals(1));
      expect(entry.writeCount, equals(1));
      entry.updateValue('v2', 2);
      expect(entry.version, equals(2));
      expect(entry.writeCount, equals(2));
      expect(entry.value, equals('v2'));
    });

    test('metadataToMap and fromMetadataMap round-trip', () {
      final entry = CacheEntry<String>(
        key: 'test',
        value: 'hello',
        sizeBytes: 10,
        ttl: const Duration(hours: 2),
      );
      entry.recordAccess();

      final map = entry.metadataToMap();
      final restored = CacheEntry.fromMetadataMap(map, 'hello');

      expect(restored.key, equals('test'));
      expect(restored.sizeBytes, equals(10));
      expect(restored.accessCount, equals(1));
      expect(restored.ttl, equals(const Duration(hours: 2)));
    });
  });

  group('TtlManager', () {
    test('onCleanup is called after interval', () async {
      var callCount = 0;
      final manager = TtlManager(
        interval: const Duration(milliseconds: 50),
        onCleanup: () async {
          callCount++;
          return 1;
        },
      );

      manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await manager.dispose();

      expect(callCount, greaterThanOrEqualTo(2));
      expect(manager.sweepCount, greaterThanOrEqualTo(2));
      expect(manager.totalExpiredRemoved, greaterThanOrEqualTo(2));
    });

    test('runNow triggers immediate cleanup', () async {
      var called = false;
      final manager = TtlManager(
        interval: const Duration(hours: 1), // long interval
        onCleanup: () async {
          called = true;
          return 0;
        },
      );

      manager.start();
      await manager.runNow();
      await manager.dispose();

      expect(called, isTrue);
    });

    test('dispose stops further sweeps', () async {
      var count = 0;
      final manager = TtlManager(
        interval: const Duration(milliseconds: 30),
        onCleanup: () async {
          count++;
          return 0;
        },
      );

      manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await manager.dispose();

      final countAfterDispose = count;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // No new sweeps after dispose
      expect(count, equals(countAfterDispose));
    });

    test('errors in onCleanup do not crash manager', () async {
      var safeCount = 0;
      final manager = TtlManager(
        interval: const Duration(milliseconds: 30),
        onCleanup: () async {
          if (safeCount == 0) {
            safeCount++;
            throw Exception('simulated failure');
          }
          safeCount++;
          return 0;
        },
      );

      manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await manager.dispose();

      // Should have continued running despite first call throwing
      expect(safeCount, greaterThan(1));
    });
  });
}
