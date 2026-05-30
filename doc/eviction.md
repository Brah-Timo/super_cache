# Eviction Policies

Configure via `CacheConfig(evictionPolicy: EvictionPolicyType.arc)`.

## ARC — Adaptive Replacement Cache (default)

ARC maintains four internal lists:

| List | Contents |
|------|----------|
| **T1** | Keys seen exactly once (recency list) |
| **T2** | Keys seen ≥ 2 times (frequency list) |
| **B1** | Ghost list: recently evicted from T1 |
| **B2** | Ghost list: recently evicted from T2 |

The balance parameter **p** adapts automatically:
- B1 ghost hit → increase p (protect recency)  
- B2 ghost hit → decrease p (protect frequency)

**Best for:** mixed workloads with unknown access patterns.

## LRU — Least Recently Used

Evicts the entry that was accessed furthest in the past.

**Best for:** temporal locality workloads (recent data is more likely to be reused).

## LFU — Least Frequently Used

Evicts the entry accessed least often.

**Best for:** stable hot-set workloads (popular items stay cached).

## Choosing a Policy

```dart
// ARC (recommended default)
evictionPolicy: EvictionPolicyType.arc

// LRU
evictionPolicy: EvictionPolicyType.lru

// LFU
evictionPolicy: EvictionPolicyType.lfu
```
