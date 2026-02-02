import Foundation
@preconcurrency import GRDB
import StorageCore
import StorageGRDB
import StorageRepo

/// Simplified storage facade with convenient CRUD operations backed by SQLite.
///
/// For caching, use `MemoryCache` or `DiskCache` separately as needed.
///
/// Usage with @StorageEntity macro:
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
/// // Observe changes (no await needed)
/// for await users in storage.observeAll(User.self) {
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

    /// Save an entity to database
    public func save<E: RegisteredEntity>(_ entity: E) async throws {
        let repo = context.makeRepository(E.self, record: E.Record.self)
        try await repo.put(entity)
    }

    /// Save multiple entities to database
    public func save<E: RegisteredEntity>(_ entities: [E]) async throws {
        let repo = context.makeRepository(E.self, record: E.Record.self)
        for entity in entities {
            try await repo.put(entity)
        }
    }

    // MARK: - Get

    /// Get an entity by ID
    public func get<E: RegisteredEntity>(_ type: E.Type, id: String) async throws -> E? {
        let repo = context.makeRepository(type, record: E.Record.self)
        return try await repo.get(id: id)
    }

    /// Get all entities
    public func all<E: RegisteredEntity>(
        _ type: E.Type,
        orderBy: String? = nil,
        ascending: Bool = true
    ) async throws -> [E] {
        let repo = context.makeRepository(type, record: E.Record.self)
        return try await repo.getAll(orderBy: orderBy, ascending: ascending)
    }

    /// Get entities with pagination
    public func page<E: RegisteredEntity>(
        _ type: E.Type,
        orderBy: String? = nil,
        ascending: Bool = true,
        limit: Int,
        offset: Int = 0
    ) async throws -> RepoPage<E> {
        let repo = context.makeRepository(type, record: E.Record.self)
        return try await repo.getPage(orderBy: orderBy, ascending: ascending, limit: limit, offset: offset)
    }

    /// Count all entities
    public func count<E: RegisteredEntity>(_ type: E.Type) async throws -> Int {
        let repo = context.makeRepository(type, record: E.Record.self)
        return try await repo.countAll()
    }

    // MARK: - Delete

    /// Delete an entity by ID
    public func delete<E: RegisteredEntity>(_ type: E.Type, id: String) async throws {
        let repo = context.makeRepository(type, record: E.Record.self)
        try await repo.delete(id: id)
    }

    /// Delete an entity
    public func delete<E: RegisteredEntity>(_ entity: E) async throws {
        let repo = context.makeRepository(E.self, record: E.Record.self)
        try await repo.delete(id: "\(entity.id)")
    }

    // MARK: - Observe

    /// Observe a single entity by ID (MainActor delivery).
    ///
    /// Values are delivered on MainActor, safe for SwiftUI views.
    public func observe<E: RegisteredEntity>(_ type: E.Type, id: String) -> AsyncStream<E?> {
        let repo = context.makeRepository(type, record: E.Record.self)
        return repo.observe(id: id)
    }

    /// Observe all entities (MainActor delivery).
    ///
    /// Values are delivered on MainActor, safe for SwiftUI views.
    public func observeAll<E: RegisteredEntity>(
        _ type: E.Type,
        orderBy: String? = nil,
        ascending: Bool = true
    ) -> AsyncStream<[E]> {
        let repo = context.makeRepository(type, record: E.Record.self)
        return repo.observeAll(orderBy: orderBy, ascending: ascending)
    }

    /// Observe all entities with deduplication (MainActor delivery, skips unchanged).
    ///
    /// Only emits when values actually change, reducing unnecessary UI updates.
    public func observeAllDistinct<E: RegisteredEntity & Equatable>(
        _ type: E.Type,
        orderBy: String? = nil,
        ascending: Bool = true
    ) -> AsyncStream<[E]> {
        let repo = context.makeRepository(type, record: E.Record.self)
        return repo.observeAllDistinct(orderBy: orderBy, ascending: ascending)
    }

    // MARK: - Query Builder

    /// Create a type-safe query builder for the entity
    ///
    /// Usage:
    /// ```swift
    /// let adults = try await storage.query(User.self)
    ///     .where { $0.age >= 18 }
    ///     .orderBy("name")
    ///     .limit(20)
    ///     .fetch()
    /// ```
    public func query<E: RegisteredEntity>(_ type: E.Type) -> Query<E> {
        Query<E>(db: context.storage.dbActor, config: context.config)
    }

    // MARK: - Relations

    /// Load a parent entity by ID (for @BelongsTo relationships)
    ///
    /// Usage:
    /// ```swift
    /// // Given Post with authorId foreign key
    /// let author = try await storage.loadParent(User.self, id: post.authorId)
    /// ```
    public func loadParent<Parent: RegisteredEntity>(
        _ type: Parent.Type,
        id: String
    ) async throws -> Parent? {
        try await get(type, id: id)
    }

    /// Load children entities by foreign key (for @HasMany relationships)
    ///
    /// Usage:
    /// ```swift
    /// // Load all comments for a post
    /// let comments = try await storage.loadChildren(Comment.self, where: "postId", equals: post.id)
    /// ```
    public func loadChildren<Child: RegisteredEntity>(
        _ type: Child.Type,
        where foreignKey: String,
        equals parentId: String,
        orderBy: String? = nil,
        ascending: Bool = true
    ) async throws -> [Child] {
        let repo = context.makeRepository(type, record: Child.Record.self)
        return try await repo.getAll(where: foreignKey, equals: parentId, orderBy: orderBy, ascending: ascending)
    }

    // MARK: - Repository Access

    /// Get a typed repository for advanced operations
    public func repository<E: RegisteredEntity>(_ type: E.Type) -> GenericRepository<E, E.Record> {
        context.makeRepository(type, record: E.Record.self)
    }

    /// Get a type-erased repository for DI
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
