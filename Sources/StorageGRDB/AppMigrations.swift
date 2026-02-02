import Foundation
@preconcurrency import GRDB
import StorageCore

public struct AppMigrations {
    public struct Options: Sendable {
        public var eraseDatabaseOnSchemaChange: Bool
        public var logger: (@Sendable (String) -> Void)?
        public init(eraseDatabaseOnSchemaChange: Bool = false, logger: (@Sendable (String) -> Void)? = nil) {
            self.eraseDatabaseOnSchemaChange = eraseDatabaseOnSchemaChange
            self.logger = logger
        }
    }

    private enum Spec: Sendable {
        case kvCache(String)
        case custom(id: String, skipIfTableExists: String?, body: @Sendable (Database) throws -> Void)
    }

    private var specs: [Spec] = []
    private var options: Options = .init()

    public init() {}

    @discardableResult
    public mutating func addKVCache(tableName: String = "kv_cache") -> Self {
        specs.append(.kvCache(tableName)); return self
    }

    /// Add a custom migration
    /// - Parameters:
    ///   - id: Unique migration identifier (e.g., "2024-01-15_create_users")
    ///   - skipIfTableExists: Skip this migration if the specified table already exists
    ///   - body: Migration body with database access
    @discardableResult
    public mutating func add(
        id: String,
        skipIfTableExists: String? = nil,
        body: @escaping @Sendable (Database) throws -> Void
    ) -> Self {
        specs.append(.custom(id: id, skipIfTableExists: skipIfTableExists, body: body)); return self
    }

    /// Add a custom migration (deprecated parameter name)
    @available(*, deprecated, renamed: "add(id:skipIfTableExists:body:)")
    @discardableResult
    public mutating func add(
        id: String,
        ifTableMissing: String?,
        body: @escaping @Sendable (Database) throws -> Void
    ) -> Self {
        specs.append(.custom(id: id, skipIfTableExists: ifTableMissing, body: body)); return self
    }

    @discardableResult
    public mutating func setOptions(_ options: Options) -> Self {
        self.options = options; return self
    }

    public func run(on writer: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()
        migrator.eraseDatabaseOnSchemaChange = options.eraseDatabaseOnSchemaChange

        for spec in specs {
            switch spec {
            case .kvCache(let table):
                let id = "storage_kv_cache_v1:\(table)"
                let log = options.logger
                migrator.registerMigration(id) { db in
                    if try !db.tableExists(table) {
                        try db.create(table: table) { t in
                            t.column("key", .text).primaryKey()
                            t.column("blob", .blob).notNull()
                            t.column("updatedAt", .datetime).notNull()
                            t.column("expiresAt", .datetime)
                            t.column("size", .integer).notNull().defaults(to: 0)
                        }
                    }
                    let idx1 = "idx_\(table)_expiresAt"
                    if try !Self.indexExists(idx1, in: db) {
                        try db.create(index: idx1, on: table, columns: ["expiresAt"])
                    }
                    let idx2 = "idx_\(table)_updatedAt"
                    if try !Self.indexExists(idx2, in: db) {
                        try db.create(index: idx2, on: table, columns: ["updatedAt"])
                    }
                    log?("[AppMigrations] Applied \(id)")
                }

            case .custom(let id, let skipIfTableExists, let body):
                let log = options.logger
                migrator.registerMigration(id) { db in
                    if let table = skipIfTableExists, try db.tableExists(table) {
                        log?("[AppMigrations] Skip \(id): table '\(table)' already exists"); return
                    }
                    try body(db); log?("[AppMigrations] Applied \(id)")
                }
            }
        }
        do {
            try migrator.migrate(writer)
        } catch {
            // Extract migration ID from error if possible
            let migrationId = (error as NSError).userInfo["migrationIdentifier"] as? String ?? "unknown"
            throw StorageError.migrationFailed(id: migrationId, underlying: error)
        }
    }

    private static func indexExists(_ name: String, in db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='index' AND name = ?)",
            arguments: [name]
        ) ?? false
    }
}
