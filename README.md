# StorageKit — Swift 6 Concurrency (GRDB 7.6.1 · iOS 18)

A cohesive storage layer for SwiftUI apps with:
- GRDB-backed persistence (SQLite)
- Two-level caching (in-memory LRU + disk KV)
- Async/await with actors and **Swift 6** concurrency checks
- A **single, unified facade** `StorageKit` for both **easy** and **advanced** starts

---

## Requirements

- iOS 18+
- Swift 6 (Complete Concurrency Checks)
- GRDB 7.6.1

---

## Modules layout

- **StorageCore** — foundational pieces (Clock, `StorageConfig` with encoder/decoder *factories*, `KeyBuilder`, `MemoryCache`)
- **StorageGRDB** — GRDB integration (`DatabaseActor`, `StorageContext`, `DiskCache`, `AppMigrations`, `ObservationBridge`)
- **StorageRepo** — `GenericRepository` (read-through/write-through), `QueryIndexStore`
- **StorageKit** — **unified facade** (this is what you import in your app)

> Internally, GRDB-facing files use `@preconcurrency import GRDB` and `StorageContext` is marked `@unchecked Sendable` because it stores GRDB types (`DatabasePool`) that are thread-safe but not annotated `Sendable` in public API. This keeps code sound under Swift 6 while preserving correctness.

---

## Quick Start

```swift
import StorageKit

// 1) Define schema
var schema = AppMigrations()
schema.addKVCache() // creates "kv_cache" table + indexes if missing
schema.add(id: "2025-08-28_create_user_profiles", ifTableMissing: "user_profiles") { db in
    try db.create(table: "user_profiles") { t in
        t.column("id", .text).primaryKey()
        t.column("name", .text).notNull()
        t.column("email", .text).notNull()
        t.column("updatedAt", .datetime).notNull()
    }
    try db.create(index: "idx_user_profiles_email", on: "user_profiles", columns: ["email"])
}

// 2) Start with defaults (Application Support; FK+WAL; sane TTL/disk quota)
let ctx = try StorageKit.start { $0 = schema }

// 3) Build a repository
typealias UserRepository = GenericRepository<UserProfileModel, UserProfileRecord>
let userRepo = ctx.makeRepository(UserProfileModel.self, record: UserProfileRecord.self)
```

---

## Advanced Start (custom location + pool options)

```swift
import StorageKit

let url = try StorageKit.defaultDatabaseURL(fileName: "custom.sqlite")
let ctx = try StorageKit.start(at: url, options: .init(
    namespace: "myapp",
    defaultTTL: 300,
    diskQuotaBytes: 30 * 1024 * 1024,
    pool: .init(
        preset: .default,                 // ["PRAGMA foreign_keys = ON", "PRAGMA journal_mode = WAL"]
        pragmasPlacement: .append,        // or .prepend
        configure: { cfg in cfg.maximumReaderCount = 4 }
    )
)) { m in
    m.addKVCache()
    m.add(id: "2025-08-28_create_user_profiles", ifTableMissing: "user_profiles") { db in
        try db.create(table: "user_profiles") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("email", .text).notNull()
            t.column("updatedAt", .datetime).notNull()
        }
    }
}
```

---

## Swift 6 Concurrency & Sendable — what’s handled for you

- **No shared encoders/decoders**: `StorageConfig` provides `makeEncoder/makeDecoder` factories to avoid sharing non‑`Sendable` instances across tasks.
- **GRDB annotation gap**: all GRDB-facing files use `@preconcurrency import GRDB` to interop cleanly with GRDB’s public types under Swift 6.
- **Context wrapper**: `StorageContext` is `@unchecked Sendable` with a clear rationale (contains `DatabasePool` which is thread-safe).
- **UI-safe observation**: repository observation delivers values on **MainActor** via `DatabaseActor.streamOnMainActor(...)` to avoid “call to main actor‑isolated instance” errors.

### Example: observing on the main thread (UI‑safe)

```swift
Task {
    for await value in userRepo.observe(id: "u1") {
        // Delivered on MainActor — safe for SwiftUI views
        print("Name:", value?.name ?? "nil")
    }
}
```

If you need the raw, immediate stream (no main-actor hop), use `DatabaseActor.streamImmediate` directly from your custom code.

---

## Repositories — read-through/write-through

**Get** tries RAM → Disk → DB (and fills caches on the way).  
**Put** writes to DB, then updates Disk and RAM (write-through).

```swift
// Get (local-first with TTL)
let profile = try await userRepo.get(id: "u1", policy: .localFirst(ttl: 300))

// Put (write-through)
if let p = profile {
    try await userRepo.put(p)
}
```

---

## DiskCache specifics

- Requires the `kv_cache` table. Add it once via `schema.addKVCache()` before using `DiskCache`.
- TTL: `expiresAt = now + ttl` if `ttl > 0` (infinite otherwise).
- Quota: every `set` triggers pruning to `diskQuotaBytes` (expired/oldest first).
- Manual cleanup:
```swift
await diskCache.pruneExpired()
```

---

## MemoryCache (standalone)

```swift
import StorageCore

let cache = MemoryCache<String, Data>(capacity: 500, defaultTTL: 300, clock: SystemClock())
await cache.set(Data([1,2,3]), for: "blob", ttl: nil)
let blob = await cache.get("blob")
await cache.removeAll()
```

---

## Migrations: `id` and `ifTableMissing`

- **`id`** — unique migration identifier; GRDB records it so each id runs **exactly once**. Do not rename/reuse a shipped id.
- **`ifTableMissing`** — guard for **CREATE** migrations. If the table already exists (prebuilt DBs, test fixtures, multi-module setups), the migration body is **skipped** instead of failing. Don’t use this for `ALTER` migrations that must always apply.

**CREATE example (guarded):**
```swift
m.add(id: "2025-09-01_create_events", ifTableMissing: "events") { db in
    try db.create(table: "events") { t in
        t.column("id", .text).primaryKey()
        t.column("title", .text).notNull()
    }
}
```

**ALTER example (unguarded):**
```swift
m.add(id: "2025-09-15_add_isArchived_to_events") { db in
    try db.alter(table: "events") { t in
        t.add(column: "isArchived", .boolean).notNull().defaults(to: false)
    }
}
```

---

## Troubleshooting (Swift 6)

- **“table already exists”** on CREATE: add `ifTableMissing: "table_name"` for that migration.
- **Indexes inside `create(table:)`**: not supported; create with `db.create(index: ...)` afterwards.

---

## FAQ

**Q: Do I need to set PRAGMAs manually?**  
A: No. The facade provides pool presets (default = `foreign_keys=ON`, `journal_mode=WAL`). You can customize via `PoolOptions`.

**Q: Can I use `MemoryCache` alone?**  
A: Yes. It’s an `actor` with `get/set/remove/removeAll`, LRU eviction, and TTL.

**Q: Can I plug Swinject?**  
A: Yes; register `StorageConfig`, `StorageContext/DatabaseActor`, `KeyBuilder`, and your repositories. The facade does not impose a DI container.

---
