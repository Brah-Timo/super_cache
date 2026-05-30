import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:super_cache/src/encryption/aes_cipher.dart';
import 'package:super_cache/src/encryption/xor_cipher.dart';
import 'package:super_cache/src/encryption/cipher.dart';
import 'package:super_cache/src/core/cache_exceptions.dart';
import 'package:super_cache/src/utils/byte_utils.dart';

void main() {
  group('AesCipher', () {
    late AesCipher cipher;

    setUp(() {
      final key = AesCipher.generateKey();
      cipher = AesCipher(key);
    });

    test('encrypt + decrypt round-trip', () {
      final plaintext = Uint8List.fromList(
        List.generate(64, (i) => i),
      );
      final ciphertext = cipher.encrypt(plaintext);
      final decrypted = cipher.decrypt(ciphertext);
      expect(ByteUtils.equal(decrypted, plaintext), isTrue);
    });

    test('encrypt produces different output each time (random IV)', () {
      final pt = Uint8List.fromList([1, 2, 3]);
      final ct1 = cipher.encrypt(pt);
      final ct2 = cipher.encrypt(pt);
      // IVs differ → ciphertexts must differ
      expect(ByteUtils.equal(ct1, ct2), isFalse);
    });

    test('ciphertext is longer than plaintext by 28 bytes', () {
      final pt = Uint8List(100);
      final ct = cipher.encrypt(pt);
      expect(ct.length, equals(100 + 28)); // 12 IV + 16 tag
    });

    test('algorithmName is AES-256-GCM', () {
      expect(cipher.algorithmName, equals('AES-256-GCM'));
    });

    test('throws InvalidKeyException for wrong key length', () {
      expect(
        () => AesCipher(List.filled(16, 0)), // 16 bytes, needs 32
        throwsA(isA<InvalidKeyException>()),
      );
    });

    test('tampered ciphertext throws CacheEncryptionException', () {
      final pt = Uint8List.fromList([10, 20, 30]);
      final ct = cipher.encrypt(pt);
      // Flip a byte in the payload
      ct[15] ^= 0xFF;
      expect(
        () => cipher.decrypt(ct),
        throwsA(isA<CacheEncryptionException>()),
      );
    });

    test('too-short ciphertext throws CacheEncryptionException', () {
      expect(
        () => cipher.decrypt(Uint8List(10)),
        throwsA(isA<CacheEncryptionException>()),
      );
    });

    test('generateKey produces 32 bytes', () {
      final key = AesCipher.generateKey();
      expect(key.length, equals(32));
    });

    test('deriveKey produces consistent output from same password+salt', () {
      const password = 'supersecret';
      final salt = List.filled(16, 0x42);
      final k1 = AesCipher.deriveKey(password, salt, iterations: 1000);
      final k2 = AesCipher.deriveKey(password, salt, iterations: 1000);
      expect(k1, equals(k2));
    });

    test('round-trip with empty plaintext', () {
      final pt = Uint8List(0);
      final ct = cipher.encrypt(pt);
      final decrypted = cipher.decrypt(ct);
      expect(decrypted.length, equals(0));
    });

    test('round-trip with large plaintext (1 MB)', () {
      final pt = Uint8List(1 * 1024 * 1024);
      for (var i = 0; i < pt.length; i++) { pt[i] = i & 0xFF; }
      final ct = cipher.encrypt(pt);
      final decrypted = cipher.decrypt(ct);
      expect(ByteUtils.equal(decrypted, pt), isTrue);
    });
  });

  group('XorCipher', () {
    test('encrypt + decrypt round-trip', () {
      final cipher = XorCipher([0xDE, 0xAD, 0xBE, 0xEF]);
      final pt = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(ByteUtils.equal(cipher.decrypt(cipher.encrypt(pt)), pt), isTrue);
    });

    test('XOR is its own inverse', () {
      final cipher = XorCipher([0xAA]);
      final pt = Uint8List.fromList([0x55, 0x33]);
      expect(cipher.encrypt(cipher.encrypt(pt)), equals(pt));
    });

    test('algorithmName is XOR', () {
      expect(XorCipher([1]).algorithmName, equals('XOR'));
    });

    test('empty key throws InvalidConfigException', () {
      expect(() => XorCipher([]), throwsA(isA<InvalidConfigException>()));
    });
  });

  group('NullCipher', () {
    test('returns data unchanged', () {
      const cipher = NullCipher();
      final data = Uint8List.fromList([1, 2, 3]);
      expect(cipher.encrypt(data), equals(data));
      expect(cipher.decrypt(data), equals(data));
    });

    test('algorithmName is none', () {
      expect(const NullCipher().algorithmName, equals('none'));
    });
  });

  group('ByteUtils', () {
    test('equal: same bytes', () {
      final a = Uint8List.fromList([1, 2, 3]);
      expect(ByteUtils.equal(a, Uint8List.fromList([1, 2, 3])), isTrue);
    });

    test('equal: different bytes', () {
      final a = Uint8List.fromList([1, 2, 3]);
      expect(ByteUtils.equal(a, Uint8List.fromList([1, 2, 4])), isFalse);
    });

    test('constantTimeEqual: same bytes', () {
      final a = Uint8List.fromList([0xDE, 0xAD]);
      expect(ByteUtils.constantTimeEqual(a, Uint8List.fromList([0xDE, 0xAD])), isTrue);
    });

    test('toHex and fromHex round-trip', () {
      final bytes = Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE]);
      expect(ByteUtils.fromHex(ByteUtils.toHex(bytes)), equals(bytes));
    });

    test('intToBytes and bytesToInt round-trip', () {
      const value = 0x0102030405;
      final bytes = ByteUtils.intToBytes(value, 5);
      expect(ByteUtils.bytesToInt(bytes), equals(value));
    });

    test('concat joins parts correctly', () {
      final a = Uint8List.fromList([1, 2]);
      final b = Uint8List.fromList([3, 4]);
      expect(ByteUtils.concat([a, b]), equals(Uint8List.fromList([1, 2, 3, 4])));
    });

    test('zeroOut fills with zeros', () {
      final key = Uint8List.fromList([1, 2, 3, 4]);
      ByteUtils.zeroOut(key);
      expect(key, equals(Uint8List(4)));
    });
  });
}
