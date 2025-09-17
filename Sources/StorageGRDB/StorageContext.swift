import Foundation
@preconcurrency import GRDB

/// Holds non-Sendable GRDB types. Marked @unchecked Sendable because GRDB's DatabasePool is thread-safe.
public struct StorageContext: @unchecked Sendable {
    public let pool: DatabasePool
    public let dbActor: DatabaseActor
    public init(pool: DatabasePool, dbActor: DatabaseActor) {
        self.pool = pool
        self.dbActor = dbActor
    }
}
