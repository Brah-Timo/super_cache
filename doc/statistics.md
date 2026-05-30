# Statistics & Monitoring

Enable with `CacheConfig(enableStatistics: true)`.

## Accessing Stats

```dart
final stats = cache.statistics;          // live CacheStatistics
final snap  = cache.statistics.snapshot(); // immutable point-in-time copy
```

## Key Metrics

| Getter | Description |
|--------|-------------|
| `hitRate` | Overall cache hit fraction (0.0–1.0) |
| `l1HitRate` | Fraction of reads served from memory |
| `l2HitRate` | Fraction of reads promoted from disk |
| `missRate` | `1.0 - hitRate` |
| `l1Hits` / `l2Hits` / `misses` | Raw counts |
| `writes` / `deletes` / `evictions` | Write-side counters |
| `ttlExpirations` | Entries removed by TTL |
| `avgReadLatencyUs` | Average read latency in microseconds |
| `avgWriteLatencyUs` | Average write latency in microseconds |
| `currentMemoryBytes` | Live L1 memory usage |
| `currentDiskBytes` | Live L2 disk usage |
| `requestsPerSecond` | Throughput estimate |
| `uptime` | Time since last reset |

## Resetting

```dart
cache.statistics.reset(); // clears all counters, restarts uptime
```

## Snapshot to Map

```dart
final map = snap.toMap(); // suitable for logging / analytics
```
