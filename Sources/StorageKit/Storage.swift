import Foundation
@preconcurrency import GRDB
import StorageCore
import StorageGRDB
import StorageRepo

/// Simplified storage facade with convenient CRUD operations backed by SQLite.
///
/// For caching, use `MemoryCache` or `DiskCache` separately as needed.
///
/// Usage:
/// ```swift
/// let ctx = try StorageKit.start()
/// let storage = ctx.facade
///
/// // Save
/// try await storage.save(user, record: UserRecord.self)
///
/// // Get
/// let user = try await storage.get(User.self, id: "1", record: UserRecord.self)
///
/// // Delete
/// try await storage.delete(User.self, id: "1", record: UserRecord.self)
///
/// // Observe changes
/// for await users in await storage.observeAll(User.self, record: UserRecord.self) {
///     print("Users updated: \(users.count)")
/// }
/// ```
public final class Storage: Sendable {
    private let context: StorageKit.Context

    /// Initialize Storage with a StorageKit context
    public init(context: StorageKit.Context) {
        self.context = context
    }

    // MARK: - Save

    /// Save an entity (write-through to database and caches)
    public func save<E: StorageKitEntity, R: StorageKitEntityRecord>(
        _ entity: E,
        record: R.Type
    ) async throws where R.E == E {
        let repo = context.makeRepository(E.self, record: R.self)
        try await repo.put(entity)
    }

    /// Save multiple entities
    public func save<E: StorageKitEntity, R: StorageKitEntityRecord>(
        _ entities: [E],
        record: R.Type
    ) async throws where R.E == E {
        let repo = context.makeRepository(E.self, record: R.self)
        for entity in entities {
            try await repo.put(entity)
        }
    }

    // MARK: - Get

    /// Get an entity by ID from database
    public func get<E: StorageKitEntity, R: StorageKitEntityRecord>(
        _ type: E.Type,
        id: String,
        record: R.Type
    ) async throws -> E? where R.E == E {
        let repo = context.makeRepository(type, record: R.self)
        return try await repo.get(id: id)
    }

    /// Get all entities
    public func all<E: StorageKitEntity, R: StorageKitEntityRecord>(
        _ type: E.Type,
        record: R.Type,
        orderBy: String? = nil,
        ascending: Bool = true
    ) async throws -> [E] where R.E == E {
        let repo = context.makeRepository(type, record: R.self)
        return try await repo.getAll(orderBy: orderBy, ascending: ascending)
    }

    /// Get entities with pagination
    public func page<E: StorageKitEntity, R: StorageKitEntityRecord>(
        _ type: E.Type,
        record: R.Type,
        orderBy: String? = nil,
        ascending: Bool = true,
        limit: Int,
        offset: Int = 0
    ) async throws -> RepoPage<E> where R.E == E {
        let repo = context.makeRepository(type, record: R.self)
        return try await repo.getPage(orderBy: orderBy, ascending: ascending, limit: limit, offset: offset)
    }

    /// Count all entities
    public func count<E: StorageKitEntity, R: StorageKitEntityRecord>(
        _ type: E.Type,
        record: R.Type
    ) async throws -> Int where R.E == E {
        let repo = context.makeRepository(type, record: R.self)
        return try await repo.countAll()
    }

    // MARK: - Delete

    /// Delete an entity by ID
    public func delete<E: StorageKitEntity, R: StorageKitEntityRecord>(
        _ type: E.Type,
        id: String,
        record: R.Type
    ) async throws where R.E == E {
        let repo = context.makeRepository(type, record: R.self)
        try await repo.delete(id: id)
    }

    /// Delete an entity
    public func delete<E: StorageKitEntity, R: StorageKitEntityRecord>(
        _ entity: E,
        record: R.Type
    ) async throws where R.E == E {
        try await delete(E.self, id: "\(entity.id)", record: R.self)
    }

    // MARK: - Observe

    /// Observe a single entity by ID (MainActor delivery)
    public func observe<E: StorageKitEntity, R: StorageKitEntityRecord>(
        _ type: E.Type,
        id: String,
        record: R.Type
    ) async -> AsyncStream<E?> where R.E == E {
        let repo = context.makeRepository(type, record: R.self)
        return await repo.observe(id: id)
    }

    /// Observe all entities (MainActor delivery)
    public func observeAll<E: StorageKitEntity, R: StorageKitEntityRecord>(
        _ type: E.Type,
        record: R.Type,
        orderBy: String? = nil,
        ascending: Bool = true
    ) async -> AsyncStream<[E]> where R.E == E {
        let repo = context.makeRepository(type, record: R.self)
        return await repo.observeAll(orderBy: orderBy, ascending: ascending)
    }

    /// Observe all entities with deduplication (MainActor delivery, skips unchanged)
    public func observeAllDistinct<E: StorageKitEntity & Equatable, R: StorageKitEntityRecord>(
        _ type: E.Type,
        record: R.Type,
        orderBy: String? = nil,
        ascending: Bool = true
    ) async -> AsyncStream<[E]> where R.E == E {
        let repo = context.makeRepository(type, record: R.self)
        return await repo.observeAllDistinct(orderBy: orderBy, ascending: ascending)
    }

    // MARK: - Direct Repository Access

    /// Get a typed repository for advanced operations
    public func repository<E: StorageKitEntity, R: StorageKitEntityRecord>(
        _ type: E.Type,
        record: R.Type
    ) -> GenericRepository<E, R> where R.E == E {
        context.makeRepository(type, record: R.self)
    }

    /// Get a type-erased repository for DI
    public func anyRepository<E: StorageKitEntity, R: StorageKitEntityRecord>(
        _ type: E.Type,
        record: R.Type
    ) -> AnyRepository<E> where R.E == E {
        context.repository(type, record: R.self)
    }
}

// MARK: - StorageKit.Context Extension

extension StorageKit.Context {
    /// Get a simplified Storage facade for convenient CRUD operations
    public var facade: Storage {
        Storage(context: self)
    }
}
