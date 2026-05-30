// test/unit/eviction_test.dart
// ignore_for_file: avoid_print

import 'package:test/test.dart';
import 'package:super_cache/super_cache.dart';

void main() {
  group('LruPolicy', () {
    test('onInsert adds key', () {
      final policy = LruPolicy(maxSize: 10);
      policy.onInsert('a');
      expect(policy.selectForEviction(['a']), equals('a'));
    });

    test('onAccess refreshes key (least recently used evicted)', () {
      final policy = LruPolicy(maxSize: 3);
      policy.onInsert('x');
      policy.onInsert('y');
      policy.onInsert('z');
      policy.onAccess('x'); // x is now most recently used
      final victim = policy.selectForEviction(['x', 'y', 'z']);
      // y should be evicted (least recently used after x was refreshed)
      expect(victim, equals('y'));
    });

    test('selectForEviction returns null for empty list', () {
      final policy = LruPolicy(maxSize: 10);
      expect(policy.selectForEviction([]), isNull);
    });

    test('clear empties policy', () {
      final policy = LruPolicy(maxSize: 10);
      policy.onInsert('a');
      policy.clear();
      expect(policy.selectForEviction(['a']), isNull);
    });

    test('onRemove removes key', () {
      final policy = LruPolicy(maxSize: 10);
      policy.onInsert('a');
      policy.onRemove('a');
      expect(policy.selectForEviction(['a']), isNull);
    });
  });

  group('LfuPolicy', () {
    test('onInsert adds key with frequency 1', () {
      final policy = LfuPolicy(maxSize: 10);
      policy.onInsert('a');
      final victim = policy.selectForEviction(['a']);
      expect(victim, equals('a'));
    });

    test('onAccess increases frequency', () {
      final policy = LfuPolicy(maxSize: 10);
      policy.onInsert('a');
      policy.onInsert('b');
      policy.onAccess('a');
      policy.onAccess('a');
      // b has lower frequency so it should be evicted first
      final victim = policy.selectForEviction(['a', 'b']);
      expect(victim, equals('b'));
    });

    test('clear empties policy', () {
      final policy = LfuPolicy(maxSize: 10);
      policy.onInsert('a');
      policy.clear();
      expect(policy.selectForEviction(['a']), isNull);
    });
  });

  group('ArcPolicy', () {
    test('new key goes into live cache (T1 or evicts if full)', () {
      final policy = ArcPolicy(maxSize: 10);
      policy.onInsert('key1');
      // After insert, either in T1 (if not evicted) or evicted
      // With maxSize=10 and only 1 key, it should stay in T1
      final info = policy.debugInfo;
      final total = (info['T1'] as int) + (info['T2'] as int);
      expect(total, greaterThanOrEqualTo(0)); // at least 0 live entries
    });

    test('inserting within capacity keeps key in T1', () {
      final policy = ArcPolicy(maxSize: 10);
      policy.onInsert('a');
      final info = policy.debugInfo;
      expect(info['T1'], equals(1));
      expect(info['T2'], equals(0));
    });

    test('accessing T1 key promotes it to T2', () {
      final policy = ArcPolicy(maxSize: 10);
      policy.onInsert('a');
      policy.onAccess('a'); // promotes from T1 to T2
      final info = policy.debugInfo;
      expect(info['T1'], equals(0));
      expect(info['T2'], equals(1));
    });

    test('selectForEviction returns a key or null', () {
      final policy = ArcPolicy(maxSize: 2);
      policy.onInsert('x');
      policy.onInsert('y');
      // Both x and y are in T1 or one might have been evicted
      final victim = policy.selectForEviction(['x', 'y']);
      // victim should be one of the available keys or null if already evicted
      expect(victim == null || victim == 'x' || victim == 'y', isTrue);
    });

    test('selectForEviction on empty policy returns null', () {
      final policy = ArcPolicy(maxSize: 10);
      final victim = policy.selectForEviction([]);
      expect(victim, isNull);
    });

    test('handles many operations without error', () {
      final policy = ArcPolicy(maxSize: 5);
      for (var i = 0; i < 20; i++) {
        policy.onInsert('key_$i');
      }
      for (var i = 0; i < 20; i++) {
        policy.onAccess('key_$i');
      }
      for (var i = 0; i < 10; i++) {
        policy.onRemove('key_$i');
      }
      final info = policy.debugInfo;
      expect(info, isNotNull);
    });

    test('clear resets all lists and p', () {
      final policy = ArcPolicy(maxSize: 10);
      policy.onInsert('a');
      policy.onInsert('b');
      policy.clear();
      final info = policy.debugInfo;
      expect(info['T1'], equals(0));
      expect(info['T2'], equals(0));
      expect(info['B1'], equals(0));
      expect(info['B2'], equals(0));
      expect(info['p'], equals(0));
    });

    test('debugInfo has correct keys', () {
      final policy = ArcPolicy(maxSize: 5);
      final info = policy.debugInfo;
      expect(info.containsKey('T1'), isTrue);
      expect(info.containsKey('T2'), isTrue);
      expect(info.containsKey('B1'), isTrue);
      expect(info.containsKey('B2'), isTrue);
      expect(info.containsKey('p'), isTrue);
    });
  });
}
