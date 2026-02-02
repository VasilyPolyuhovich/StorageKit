import Foundation
@preconcurrency import GRDB
import StorageCore
import StorageGRDB

public enum ReadPolicy: Sendable {
    case memoryOnly
    case localFirst(ttl: TimeInterval?)
    case databaseOnly
}

public struct GenericRepository<E: StorageKitEntity, R: StorageKitEntityRecord>: Sendable where R.E == E {
    public typealias Key = String

    private let db: DatabaseActor
    private let ram: MemoryCache<Key, E>
    private let disk: DiskCache<E>
    private let keys: KeyBuilder
    private let cfg: StorageConfig

    public init(
        db: DatabaseActor,
        ram: MemoryCache<Key, E>,
        disk: DiskCache<E>,
        keys: KeyBuilder,
        config: StorageConfig
    ) {
        self.db = db; self.ram = ram; self.disk = disk; self.keys = keys; self.cfg = config
    }

    private func makeKey(for id: String) -> Key { keys.entityKey(E.self, id: id) }

    public func get(id: String, policy: ReadPolicy) async throws -> E? {
        let key = makeKey(for: id)

        switch policy {
        case .memoryOnly, .localFirst:
            if let hit = await ram.get(key) { return hit }
            if let v: E = await disk.get(key) { await ram.set(v, for: key, ttl: nil); return v }
            if case .memoryOnly = policy { return nil }
            fallthrough
        case .databaseOnly:
            let entity: E? = try await db.read { db in
                if let rec = try R.fetchOne(db, key: id) { return rec.asEntity() }
                return nil
            }
            if let e = entity {
                await disk.set(e, for: key, ttl: cfg.defaultTTL)
                await ram.set(e, for: key, ttl: nil)
            }
            return entity
        }
    }

    public func put(_ entity: E) async throws {
        let now = cfg.clock.now
        try await db.write { db in try R.from(entity, now: now).save(db) }
        let key = makeKey(for: "\(entity.id)")
        await ram.set(entity, for: key, ttl: nil)
        await disk.set(entity, for: key, ttl: cfg.defaultTTL)
    }

    public func delete(id: String) async throws {
        try await db.write { db in _ = try R.deleteOne(db, key: id) }
        let key = makeKey(for: id)
        await ram.remove(key)
        await disk.remove(key)
    }

    /// UI-friendly observation: values are delivered on MainActor.
    public func observe(id: String) async -> AsyncStream<E?> {
        await db.streamOnMainActor(bufferingPolicy: .bufferingNewest(1)) { db in
            try R.fetchOne(db, key: id)?.asEntity()
        }
    }
    
    /// Live stream of all entities (MainActor)
    public func observeAll(orderBy: String? = nil,
                           ascending: Bool = true) async -> AsyncStream<[E]> {
        await db.streamOnMainActor(bufferingPolicy: .bufferingNewest(1)) { db in
            func fetch(orderColumn: String) throws -> [E] {
                let order = ascending ? Column(orderColumn).asc : Column(orderColumn).desc
                return try R.order(order).fetchAll(db).map { $0.asEntity() }
            }
            
            if let col = orderBy, (try? fetch(orderColumn: col)) != nil {
                return try fetch(orderColumn: col)
            }
            return try fetch(orderColumn: "id")
        }
    }
    
    /// Distinct stream (Equatable) to reduce UI redraws.
    public func observeAllDistinct(orderBy: String? = nil,
                                   ascending: Bool = true) async -> AsyncStream<[E]> where E: Equatable {
        await db.streamDistinctOnMainActor(bufferingPolicy: .bufferingNewest(1)) { db in
            func fetch(orderColumn: String) throws -> [E] {
                let order = ascending ? Column(orderColumn).asc : Column(orderColumn).desc
                return try R.order(order).fetchAll(db).map { $0.asEntity() }
            }
            
            if let col = orderBy, (try? fetch(orderColumn: col)) != nil {
                return try fetch(orderColumn: col)
            }
            return try fetch(orderColumn: "id")
        }
    }
    
    /// Fetch all entities once
    public func getAll(orderBy: String? = nil,
                       ascending: Bool = true) async throws -> [E] {
        try await db.read { db in
            func fetch(orderColumn: String) throws -> [E] {
                let order = ascending ? Column(orderColumn).asc : Column(orderColumn).desc
                return try R.order(order).fetchAll(db).map { $0.asEntity() }
            }
            
            if let col = orderBy, (try? fetch(orderColumn: col)) != nil {
                return try fetch(orderColumn: col)
            }
            // fallback: primary key column is typically "id"
            return try fetch(orderColumn: "id")
        }
    }
    
    // MARK: - Paging

    public func getAll(orderBy: String? = nil,
                       ascending: Bool = true,
                       limit: Int? = nil,
                       offset: Int = 0) async throws -> [E] {
        try await db.read { db in
            func fetch(_ col: String) throws -> [E] {
                var request = R.order(ascending ? Column(col).asc : Column(col).desc)
                if let lim = limit, lim > 0 { request = request.limit(lim, offset: max(0, offset)) }
                return try request.fetchAll(db).map { $0.asEntity() }
            }
            if let col = orderBy, (try? fetch(col)) != nil { return try fetch(col) }
            return try fetch("id")
        }
    }

    public func countAll() async throws -> Int {
        try await db.read { db in try R.fetchCount(db) }
    }

    public func getPage(orderBy: String? = nil,
                        ascending: Bool = true,
                        limit: Int,
                        offset: Int = 0) async throws -> RepoPage<E> {
        precondition(limit > 0, "limit must be > 0")
        let items = try await getAll(orderBy: orderBy, ascending: ascending, limit: limit, offset: offset)
        let hasMore = items.count == limit
        return RepoPage(items: items, nextOffset: offset + items.count, hasMore: hasMore)
    }
}

public struct AnyRepository<E: StorageKitEntity>: Sendable {
    private let _get:        @Sendable (String, ReadPolicy) async throws -> E?
    private let _put:        @Sendable (E) async throws -> Void
    private let _delete:     @Sendable (String) async throws -> Void
    private let _observe:    @Sendable (String) async -> AsyncStream<E?>
    private let _getAll:     @Sendable (String?, Bool, Int?, Int) async throws -> [E]
    private let _observeAll: @Sendable (String?, Bool) async -> AsyncStream<[E]>
    private let _countAll:   @Sendable () async throws -> Int
    private let _getPage: @Sendable (String?, Bool, Int, Int) async throws -> RepoPage<E>
    private let _observeAllDistinct: @Sendable (String?, Bool) async -> AsyncStream<[E]>
    
    public init<R: StorageKitEntityRecord>(_ repo: GenericRepository<E, R>) where R.E == E {
        _get        = { id, pol in try await repo.get(id: id, policy: pol) }
        _put        = { e in try await repo.put(e) }
        _delete     = { id in try await repo.delete(id: id) }
        _observe    = { id in await repo.observe(id: id) }
        _getAll     = { col, asc, lim, off in try await repo.getAll(orderBy: col, ascending: asc, limit: lim, offset: off) }
        _observeAll = { col, asc in await repo.observeAll(orderBy: col, ascending: asc) }
        _countAll   = { try await repo.countAll() }
        _getPage = { col, asc, lim, off in
            try await repo.getPage(orderBy: col, ascending: asc, limit: lim, offset: off)
        }
        _observeAllDistinct = { col, asc in await repo.observeAllDistinct(orderBy: col, ascending: asc) }
    }
    
    // single
    public func get(id: String, policy: ReadPolicy) async throws -> E? { try await _get(id, policy) }
    public func put(_ entity: E) async throws { try await _put(entity) }
    public func delete(id: String) async throws { try await _delete(id) }
    public func observe(id: String) async -> AsyncStream<E?> { await _observe(id) }
    
    // many
    public func getAll(orderBy: String? = nil,
                       ascending: Bool = true,
                       limit: Int? = nil,
                       offset: Int = 0) async throws -> [E] {
        try await _getAll(orderBy, ascending, limit, offset)
    }
    public func observeAll(orderBy: String? = nil,
                           ascending: Bool = true) async -> AsyncStream<[E]> {
        await _observeAll(orderBy, ascending)
    }
    public func observeAllDistinct(orderBy: String? = nil,
                                   ascending: Bool = true) async -> AsyncStream<[E]> {
        await _observeAllDistinct(orderBy, ascending)
    }
    public func countAll() async throws -> Int { try await _countAll() }
    public func getPage(orderBy: String? = nil,
                        ascending: Bool = true,
                        limit: Int,
                        offset: Int = 0) async throws -> RepoPage<E> {
        try await _getPage(orderBy, ascending, limit, offset)
    }
}
