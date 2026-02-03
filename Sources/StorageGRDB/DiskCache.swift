import Foundation
@preconcurrency import GRDB
import StorageCore

struct KVRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "kv_cache"
    var key: String
    var blob: Data
    var updatedAt: Date
    var expiresAt: Date?
    var size: Int
}

public actor DiskCache<Value: Codable & Sendable> {
    public typealias Key = String
    public typealias ErrorHandler = @Sendable (String, Error) -> Void

    private let db: DatabaseActor
    private let cfg: StorageConfig
    private let onError: ErrorHandler?

    public init(db: DatabaseActor, config: StorageConfig, onError: ErrorHandler? = nil) {
        self.db = db
        self.cfg = config
        self.onError = onError
    }

    public func get(_ key: String) async -> Value? {
        let now = self.cfg.clock.now
        do {
            let blob: Data? = try await db.read { db in
                guard let row = try KVRow.fetchOne(db, key: key) else { return nil }
                if let exp = row.expiresAt, exp < now {
                    try row.delete(db); return nil
                }
                return row.blob
            }
            guard let blob else { return nil }
            let dec = self.cfg.makeDecoder()
            return try dec.decode(Value.self, from: blob)
        } catch {
            onError?("DiskCache.get(\(key))", error)
            return nil
        }
    }

    public func set(_ value: Value, for key: String, ttl: TimeInterval?) async {
        let now = self.cfg.clock.now
        let ttlVal = ttl ?? self.cfg.defaultTTL
        let expiresAt: Date? = ttlVal > 0 ? now.addingTimeInterval(ttlVal) : nil
        let quota = self.cfg.diskQuotaBytes
        do {
            let enc = self.cfg.makeEncoder()
            let data = try enc.encode(value)
            try await db.write { db in
                try KVRow(key: key, blob: data, updatedAt: now, expiresAt: expiresAt, size: data.count).save(db)
                try Self.pruneToQuota(db, maxBytes: quota)
            }
        } catch {
            onError?("DiskCache.set(\(key))", error)
        }
    }

    public func remove(_ key: String) async {
        do {
            _ = try await db.write { db in try KVRow.deleteOne(db, key: key) }
        } catch {
            onError?("DiskCache.remove(\(key))", error)
        }
    }

    public func removeAll() async {
        do {
            _ = try await db.write { db in try KVRow.deleteAll(db) }
        } catch {
            onError?("DiskCache.removeAll()", error)
        }
    }

    public func pruneExpired() async {
        let now = self.cfg.clock.now
        do {
            try await db.write { db in
                try db.execute(sql: "DELETE FROM kv_cache WHERE expiresAt IS NOT NULL AND expiresAt < ?", arguments: [now])
            }
        } catch {
            onError?("DiskCache.pruneExpired()", error)
        }
    }

    private static func pruneToQuota(_ db: Database, maxBytes: Int) throws {
        let total = try Int.fetchOne(db, sql: "SELECT IFNULL(SUM(size),0) FROM kv_cache") ?? 0
        if total <= maxBytes { return }
        let cursor = try Row.fetchCursor(db, sql: "SELECT key FROM kv_cache ORDER BY COALESCE(expiresAt, updatedAt) ASC")
        var bytes = total
        while bytes > maxBytes, let row = try cursor.next() {
            let key: String = row["key"]
            if let r = try KVRow.fetchOne(db, key: key) {
                bytes -= r.size
                try r.delete(db)
            }
        }
    }
}
