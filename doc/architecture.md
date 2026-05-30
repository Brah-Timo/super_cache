# Architecture

super_cache uses a **two-layer (L1 + L2) architecture** inspired by CPU cache
hierarchies.

```
  Your Code
      │
      ▼
  SuperCache  ──── public API
      │
      ▼
  CacheOrchestrator
  ┌──────────────────────────────────────────┐
  │  L1 MemoryCache  ← O(1) HashMap          │
  │  L2 DiskCache    ← O(1) B-Index seek     │
  │  WriteBuffer     ← batched async I/O     │
  │  TtlManager      ← periodic TTL cleanup  │
  └──────────────────────────────────────────┘
      │
      ▼
  StorageEngine  (DartIoStorage / WebStorage)
      │
      ▼
  IndexManager   (B-Index in memory + .idx file)
```

---

## L1 — Memory Cache

- **Type:** `HashMap<String, CacheEntry>`
- **Speed:** sub-microsecond reads (no I/O)
- **Eviction:** configurable (ARC / LRU / LFU)
- **TTL:** checked lazily on each access; periodic cleanup via `TtlManager`

## L2 — Disk Cache

- **Type:** append-only flat binary file (`<box>.dat`)
- **Index:** in-memory B-Index backed by `<box>.idx` for O(1) seeks
- **Speed:** single seek + read per miss (~1–5 µs on SSD)
- **Compaction:** removes tombstoned entries; triggered automatically or manually

## Write Path

### Write-Behind (default)

```
put(key, value)
  └─ L1.put()        ← synchronous, always
  └─ WriteBuffer.enqueue()
         │
         └─ (every 500 ms or 100 pending ops)
              └─ L2.putRaw(batch)  ← async
```

After a `put`, the value is **immediately readable** from `get` because L1 is
updated synchronously.  Crash safety depends on `CacheConfig.syncWrites`.

### Sync Writes (`CacheConfig.syncWrites = true`)

```
put(key, value)
  └─ L1.put()    ← synchronous
  └─ await L2.putRaw()  ← blocks until disk flush
```

## Read Path

```
get(key)
  └─ L1.get()   → hit?  return immediately  ✓
  └─ L2.get()   → hit?  decode → promote to L1 → return  ✓
  └─ return null (miss)
```

L2 hits trigger automatic **promotion** to L1 so the next access is an L1 hit.

---

## TTL Management

`TtlManager` runs a periodic timer (default every 60 s) that scans L1 for
expired entries.  L2 TTL cleanup is deferred to compaction runs for performance.

---

## Eviction Policies

| Policy | Description |
|--------|-------------|
| **ARC** (default) | Adaptive Replacement Cache — self-tuning, balances recency and frequency |
| **LRU** | Least Recently Used |
| **LFU** | Least Frequently Used |

See [Eviction Policies](eviction.md) for details.
