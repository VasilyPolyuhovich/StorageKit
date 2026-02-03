import Foundation
@preconcurrency import GRDB
import StorageCore
import StorageGRDB

public actor QueryIndexStore: Sendable {
    public struct Item: Codable, Sendable, Equatable {
        public let id: String
        public let updatedAt: Date
        public init(id: String, updatedAt: Date) { self.id = id; self.updatedAt = updatedAt }
    }

    private let db: DatabaseActor
    private let table: String

    /// Initialize QueryIndexStore with table name validation
    /// - Parameters:
    ///   - db: Database actor for operations
    ///   - tableName: Table name (must be alphanumeric with underscores only)
    /// - Throws: StorageError.invalidTableName if table name contains invalid characters
    public init(db: DatabaseActor, tableName: String = "query_index") throws {
        guard Self.isValidTableName(tableName) else {
            throw StorageError.invalidTableName(tableName)
        }
        self.db = db
        self.table = tableName
    }

    /// Validate table name to prevent SQL injection
    private static func isValidTableName(_ name: String) -> Bool {
        // Only allow: starts with letter or underscore, followed by letters, numbers, underscores
        // Max length 64 characters (SQLite limit is higher but this is reasonable)
        let pattern = "^[a-zA-Z_][a-zA-Z0-9_]{0,63}$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    public func migrate() async throws {
        try await db.write { [table] db in
            if try !db.tableExists(table) {
                try db.create(table: table) { t in
                    t.column("query", .text).notNull()
                    t.column("id", .text).notNull()
                    t.column("updatedAt", .datetime).notNull()
                    t.primaryKey(["query", "id"])
                }
            }
        }
    }

    public func save(query: String, ids: [Item]) async throws {
        try await db.write { [table] db in
            for item in ids {
                try db.execute(sql: "INSERT OR REPLACE INTO \(table) (query, id, updatedAt) VALUES (?, ?, ?)",
                               arguments: [query, item.id, item.updatedAt])
            }
        }
    }

    public func load(query: String) async throws -> [Item] {
        try await db.read { [table] db in
            try Row.fetchAll(db, sql: "SELECT id, updatedAt FROM \(table) WHERE query = ? ORDER BY updatedAt DESC", arguments: [query]).map {
                Item(id: $0["id"], updatedAt: $0["updatedAt"])
            }
        }
    }

    public func clear(query: String) async throws {
        _ = try await db.write { [table] db in
            try db.execute(sql: "DELETE FROM \(table) WHERE query = ?", arguments: [query])
        }
    }
}
