# Configuration Reference

All options are set via `CacheConfig` (immutable, `const`-friendly).

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `boxName` | `String` | `'default'` | Storage file name |
| `maxMemoryEntries` | `int` | `1000` | Max entries in L1 |
| `maxMemorySizeBytes` | `int` | `50 MB` | Max L1 memory |
| `maxDiskSizeBytes` | `int` | `256 MB` | Max L2 disk |
| `defaultTtl` | `Duration?` | `null` | TTL applied to every put unless overridden |
| `evictionPolicy` | `EvictionPolicyType` | `arc` | `arc` / `lru` / `lfu` |
| `enableDiskCache` | `bool` | `true` | Disable to use L1-only |
| `syncWrites` | `bool` | `false` | Block until L2 flush |
| `writeBufferSize` | `int` | `100` | Ops before auto-flush |
| `writeBufferFlushInterval` | `Duration` | `500ms` | Timer-based flush |
| `encryptionKey` | `Uint8List?` | `null` | AES-256-GCM key (32 bytes) |
| `enableStatistics` | `bool` | `false` | Track hit/miss/latency |
| `enableLogging` | `bool` | `false` | Internal debug logging |
| `autoCompact` | `bool` | `true` | Periodic disk compaction |

## Example

```dart
const config = CacheConfig(
  maxMemoryEntries: 5000,
  maxMemorySizeBytes: 100 * 1024 * 1024,
  defaultTtl: Duration(hours: 24),
  evictionPolicy: EvictionPolicyType.arc,
  writeBufferSize: 200,
  enableStatistics: true,
);
```
