import Foundation
@preconcurrency import GRDB
import StorageCore
import StorageGRDB
import StorageRepo

/// Simplified storage facade with convenient CRUD operations backed by SQLite.
///
/// For caching, use `MemoryCache` or `DiskCache` separately as needed.
///
/// Usage with @StorageEntity macro (recommended - no record: parameter needed):
/// ```swift
/// @StorageEntity
/// struct User {
///     var id: String
///     var name: String
/// }
///
/// let ctx = try StorageKit.start(...)
/// let storage = ctx.facade
///
/// // Save
/// try await storage.save(user)
///
/// // Get
/// let user = try await storage.get(User.self, id: "1")
///
/// // Delete
/// try await storage.delete(User.self, id: "1")
///
/// // Observe changes
/// for await users in await storage.observeAll(User.self) {
///     print("Users updated: \(users.count)")
/// }
/// ```
///
/// Legacy usage (explicit record: parameter):
/// ```swift
/// try await storage.save(user, record: UserRecord.self)
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

// MARK: - Simplified API (no record: parameter needed)

extension Storage {

    // MARK: - Save (Simplified)

    /// Save an entity (infers Record type from RegisteredEntity conformance)
    public func save<E: RegisteredEntity>(_ entity: E) async throws {
        try await save(entity, record: E.Record.self)
    }

    /// Save multiple entities (infers Record type from RegisteredEntity conformance)
    public func save<E: RegisteredEntity>(_ entities: [E]) async throws {
        try await save(entities, record: E.Record.self)
    }

    // MARK: - Get (Simplified)

    /// Get an entity by ID (infers Record type from RegisteredEntity conformance)
    public func get<E: RegisteredEntity>(_ type: E.Type, id: String) async throws -> E? {
        try await get(type, id: id, record: E.Record.self)
    }

    /// Get all entities (infers Record type from RegisteredEntity conformance)
    public func all<E: RegisteredEntity>(
        _ type: E.Type,
        orderBy: String? = nil,
        ascending: Bool = true
    ) async throws -> [E] {
        try await all(type, record: E.Record.self, orderBy: orderBy, ascending: ascending)
    }

    /// Get entities with pagination (infers Record type from RegisteredEntity conformance)
    public func page<E: RegisteredEntity>(
        _ type: E.Type,
        orderBy: String? = nil,
        ascending: Bool = true,
        limit: Int,
        offset: Int = 0
    ) async throws -> RepoPage<E> {
        try await page(type, record: E.Record.self, orderBy: orderBy, ascending: ascending, limit: limit, offset: offset)
    }

    /// Count all entities (infers Record type from RegisteredEntity conformance)
    public func count<E: RegisteredEntity>(_ type: E.Type) async throws -> Int {
        try await count(type, record: E.Record.self)
    }

    // MARK: - Delete (Simplified)

    /// Delete an entity by ID (infers Record type from RegisteredEntity conformance)
    public func delete<E: RegisteredEntity>(_ type: E.Type, id: String) async throws {
        try await delete(type, id: id, record: E.Record.self)
    }

    /// Delete an entity (infers Record type from RegisteredEntity conformance)
    public func delete<E: RegisteredEntity>(_ entity: E) async throws {
        try await delete(entity, record: E.Record.self)
    }

    // MARK: - Observe (Simplified)

    /// Observe a single entity by ID (infers Record type from RegisteredEntity conformance)
    public func observe<E: RegisteredEntity>(_ type: E.Type, id: String) async -> AsyncStream<E?> {
        await observe(type, id: id, record: E.Record.self)
    }

    /// Observe all entities (infers Record type from RegisteredEntity conformance)
    public func observeAll<E: RegisteredEntity>(
        _ type: E.Type,
        orderBy: String? = nil,
        ascending: Bool = true
    ) async -> AsyncStream<[E]> {
        await observeAll(type, record: E.Record.self, orderBy: orderBy, ascending: ascending)
    }

    /// Observe all entities with deduplication (infers Record type from RegisteredEntity conformance)
    public func observeAllDistinct<E: RegisteredEntity & Equatable>(
        _ type: E.Type,
        orderBy: String? = nil,
        ascending: Bool = true
    ) async -> AsyncStream<[E]> {
        await observeAllDistinct(type, record: E.Record.self, orderBy: orderBy, ascending: ascending)
    }

    // MARK: - Repository (Simplified)

    /// Get a typed repository (infers Record type from RegisteredEntity conformance)
    public func repository<E: RegisteredEntity>(_ type: E.Type) -> GenericRepository<E, E.Record> {
        context.makeRepository(type, record: E.Record.self)
    }

    /// Get a type-erased repository (infers Record type from RegisteredEntity conformance)
    public func anyRepository<E: RegisteredEntity>(_ type: E.Type) -> AnyRepository<E> {
        context.repository(type, record: E.Record.self)
    }
}

// MARK: - StorageKit.Context Extension

extension StorageKit.Context {
    /// Get a simplified Storage facade for convenient CRUD operations
    public var facade: Storage {
        Storage(context: self)
    }
}
