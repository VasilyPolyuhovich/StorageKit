import Foundation
@preconcurrency import GRDB
import StorageCore
import StorageGRDB

/// Simple repository for entity CRUD operations backed by SQLite.
/// For caching, use MemoryCache or DiskCache separately as needed.
public struct GenericRepository<E: StorageKitEntity, R: StorageKitEntityRecord>: Sendable where R.E == E {
    public typealias Key = String

    private let db: DatabaseActor
    private let keys: KeyBuilder
    private let cfg: StorageConfig

    public init(
        db: DatabaseActor,
        keys: KeyBuilder,
        config: StorageConfig
    ) {
        self.db = db
        self.keys = keys
        self.cfg = config
    }

    private func makeKey(for id: String) -> Key { keys.entityKey(E.self, id: id) }

    // MARK: - CRUD

    /// Fetch entity by ID from database
    public func get(id: String) async throws -> E? {
        try await db.read { db in
            try R.fetchOne(db, key: id)?.asEntity()
        }
    }

    /// Save entity to database
    public func put(_ entity: E) async throws {
        let now = cfg.clock.now
        try await db.write { db in try R.from(entity, now: now).save(db) }
    }

    /// Delete entity from database
    public func delete(id: String) async throws {
        try await db.write { db in _ = try R.deleteOne(db, key: id) }
    }

    // MARK: - Observation

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
            try Self.fetchOrdered(db: db, orderBy: orderBy, ascending: ascending)
        }
    }

    /// Distinct stream (Equatable) to reduce UI redraws.
    public func observeAllDistinct(orderBy: String? = nil,
                                   ascending: Bool = true) async -> AsyncStream<[E]> where E: Equatable {
        await db.streamDistinctOnMainActor(bufferingPolicy: .bufferingNewest(1)) { db in
            try Self.fetchOrdered(db: db, orderBy: orderBy, ascending: ascending)
        }
    }

    // MARK: - Fetch All

    /// Fetch all entities once
    public func getAll(orderBy: String? = nil,
                       ascending: Bool = true) async throws -> [E] {
        try await db.read { db in
            try Self.fetchOrdered(db: db, orderBy: orderBy, ascending: ascending)
        }
    }

    /// Fetch all with limit/offset
    public func getAll(orderBy: String? = nil,
                       ascending: Bool = true,
                       limit: Int? = nil,
                       offset: Int = 0) async throws -> [E] {
        try await db.read { db in
            try Self.fetchOrdered(db: db, orderBy: orderBy, ascending: ascending, limit: limit, offset: offset)
        }
    }

    public func countAll() async throws -> Int {
        try await db.read { db in try R.fetchCount(db) }
    }

    // MARK: - Paging

    public func getPage(orderBy: String? = nil,
                        ascending: Bool = true,
                        limit: Int,
                        offset: Int = 0) async throws -> RepoPage<E> {
        precondition(limit > 0, "limit must be > 0")
        let items = try await getAll(orderBy: orderBy, ascending: ascending, limit: limit, offset: offset)
        let hasMore = items.count == limit
        return RepoPage(items: items, nextOffset: offset + items.count, hasMore: hasMore)
    }

    // MARK: - Private Helpers

    private static func fetchOrdered(db: Database,
                                     orderBy: String?,
                                     ascending: Bool,
                                     limit: Int? = nil,
                                     offset: Int = 0) throws -> [E] {
        let col = orderBy ?? "id"
        let order = ascending ? Column(col).asc : Column(col).desc
        var request = R.order(order)
        if let lim = limit, lim > 0 {
            request = request.limit(lim, offset: max(0, offset))
        }
        return try request.fetchAll(db).map { $0.asEntity() }
    }
}

// MARK: - Type-Erased Repository

public struct AnyRepository<E: StorageKitEntity>: Sendable {
    private let _get:        @Sendable (String) async throws -> E?
    private let _put:        @Sendable (E) async throws -> Void
    private let _delete:     @Sendable (String) async throws -> Void
    private let _observe:    @Sendable (String) async -> AsyncStream<E?>
    private let _getAll:     @Sendable (String?, Bool, Int?, Int) async throws -> [E]
    private let _observeAll: @Sendable (String?, Bool) async -> AsyncStream<[E]>
    private let _countAll:   @Sendable () async throws -> Int
    private let _getPage:    @Sendable (String?, Bool, Int, Int) async throws -> RepoPage<E>
    private let _observeAllDistinct: @Sendable (String?, Bool) async -> AsyncStream<[E]>

    public init<R: StorageKitEntityRecord>(_ repo: GenericRepository<E, R>) where R.E == E {
        _get        = { id in try await repo.get(id: id) }
        _put        = { e in try await repo.put(e) }
        _delete     = { id in try await repo.delete(id: id) }
        _observe    = { id in await repo.observe(id: id) }
        _getAll     = { col, asc, lim, off in try await repo.getAll(orderBy: col, ascending: asc, limit: lim, offset: off) }
        _observeAll = { col, asc in await repo.observeAll(orderBy: col, ascending: asc) }
        _countAll   = { try await repo.countAll() }
        _getPage    = { col, asc, lim, off in try await repo.getPage(orderBy: col, ascending: asc, limit: lim, offset: off) }
        _observeAllDistinct = { col, asc in await repo.observeAllDistinct(orderBy: col, ascending: asc) }
    }

    // single
    public func get(id: String) async throws -> E? { try await _get(id) }
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
