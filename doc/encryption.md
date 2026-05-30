# Encryption

super_cache supports **AES-256-GCM** authenticated encryption via `AesCipher`.

## Generating a Key

```dart
final key = AesCipher.generateKey(); // 32 random bytes
// Store key securely: flutter_secure_storage, etc.
```

## Encrypted Cache

```dart
await SuperCache.init(
  name: 'secure',
  config: CacheConfig(
    boxName: 'secure_box',
    encryptionKey: key,
    maxMemoryEntries: 100,
  ),
);
final secureCache = SuperCache.named('secure');
await secureCache.put('secret', 'sensitive_data');
```

## How It Works

Each value is encrypted with a **random 12-byte IV** before being written to
disk. The IV is stored alongside the ciphertext. AES-256-GCM provides both
confidentiality and integrity (authentication tag).

L1 (memory) stores **plaintext** values for performance. Only L2 (disk) data
is encrypted.

## XorCipher (dev/testing only)

```dart
// NOT secure — for development/testing only
config: CacheConfig(encryptionKey: myKey, cipher: XorCipher()),
```
