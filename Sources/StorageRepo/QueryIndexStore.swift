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

    public init(db: DatabaseActor, tableName: String = "query_index") {
        self.db = db; self.table = tableName
    }

    public func migrate() async throws {
        try await db.write { db in
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
        try await db.write { db in
            for item in ids {
                try db.execute(sql: "INSERT OR REPLACE INTO \(table) (query, id, updatedAt) VALUES (?, ?, ?)",
                               arguments: [query, item.id, item.updatedAt])
            }
        }
    }

    public func load(query: String) async throws -> [Item] {
        try await db.read { db in
            try Row.fetchAll(db, sql: "SELECT id, updatedAt FROM \(table) WHERE query = ? ORDER BY updatedAt DESC", arguments: [query]).map {
                Item(id: $0["id"], updatedAt: $0["updatedAt"])
            }
        }
    }

    public func clear(query: String) async throws {
        _ = try await db.write { db in
            try db.execute(sql: "DELETE FROM \(table) WHERE query = ?", arguments: [query])
        }
    }
}
