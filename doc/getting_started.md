# Getting Started with super_cache

super_cache is a blazing-fast, pure-Dart, dual-layer (L1 memory + L2 disk) cache
package for Flutter and Dart. It offers **ARC adaptive eviction**, TTL support,
AES-256-GCM encryption, isolate safety, and zero native dependencies.

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  super_cache: ^1.0.0
```

Then run:

```bash
flutter pub get
# or (pure Dart)
dart pub get
```

---

## Quick Start

### 1. Initialize

Call `SuperCache.init()` once at app startup — before any cache operations.

```dart
import 'package:super_cache/super_cache.dart';

Future<void> main() async {
  await SuperCache.init(
    config: const CacheConfig(
      maxMemoryEntries: 2000,
      defaultTtl: Duration(hours: 24),
      evictionPolicy: EvictionPolicyType.arc,
      enableStatistics: true,
    ),
  );
}
```

### 2. Write and Read

```dart
final cache = SuperCache.instance;

// Write
await cache.put('greeting', 'Hello, World!');
await cache.put('user', myUser, ttl: const Duration(hours: 1));

// Read (returns null if missing or expired)
final greeting = await cache.get<String>('greeting');
final user = await cache.get<UserProfile>('user');
```

### 3. Cache-Aside Pattern

```dart
final config = await cache.getOrPut(
  'app_config',
  () => fetchConfigFromServer(),
  ttl: const Duration(minutes: 30),
);
```

### 4. Clean Up

```dart
await cache.dispose();
```

---

## Next Steps

- [Architecture](architecture.md) — how L1/L2 and the write buffer work
- [Custom Adapters](adapters.md) — serialize your own types
- [Configuration Reference](configuration.md) — all `CacheConfig` options
- [Encryption](encryption.md) — AES-256-GCM encrypted caches
- [Statistics & Monitoring](statistics.md) — hit rates, latency, throughput
