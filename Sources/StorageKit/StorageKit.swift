import Foundation

// Re-export all modules so users only need `import StorageKit`
@_exported import StorageKitMacros  // includes @StorageEntity macro + StorageCore + StorageGRDB + GRDB
@_exported import StorageRepo       // includes GenericRepository, AnyRepository

public enum StorageKit {

    // MARK: - Simplified Configuration Types

    /// Cache TTL duration with convenient factory methods
    public struct CacheDuration: Sendable {
        public let seconds: TimeInterval

        public init(seconds: TimeInterval) { self.seconds = seconds }

        public static func seconds(_ value: Int) -> CacheDuration { .init(seconds: TimeInterval(value)) }
        public static func minutes(_ value: Int) -> CacheDuration { .init(seconds: TimeInterval(value * 60)) }
        public static func hours(_ value: Int) -> CacheDuration { .init(seconds: TimeInterval(value * 3600)) }
        public static let `default`: CacheDuration = .minutes(5)
    }

    /// Disk quota with convenient factory methods
    public struct DiskQuota: Sendable {
        public let bytes: Int

        public init(bytes: Int) { self.bytes = bytes }

        public static func megabytes(_ value: Int) -> DiskQuota { .init(bytes: value * 1024 * 1024) }
        public static func gigabytes(_ value: Int) -> DiskQuota { .init(bytes: value * 1024 * 1024 * 1024) }
        public static let `default`: DiskQuota = .megabytes(30)
    }

    public struct Context: Sendable {
        public let storage: StorageContext
        public let config: StorageConfig
        public let keys: KeyBuilder

        public init(storage: StorageContext, config: StorageConfig, keys: KeyBuilder) {
            self.storage = storage; self.config = config; self.keys = keys
        }

        public func makeRepository<E: StorageKitEntity, R: StorageKitEntityRecord>(_: E.Type, record _: R.Type) -> GenericRepository<E, R> where R.E == E {
            GenericRepository<E, R>(db: storage.dbActor, keys: keys, config: config)
        }

        /// Type-erased repository for easier DI
        public func repository<E: StorageKitEntity, R: StorageKitEntityRecord>(_: E.Type, record _: R.Type) -> AnyRepository<E> where R.E == E {
            AnyRepository(makeRepository(E.self, record: R.self))
        }
    }

    // MARK: - Simplified Start API

    /// Start StorageKit with zero configuration (uses defaults)
    /// - Returns: Configured storage context with kv_cache table ready
    public static func start() throws -> Context {
        try start(fileName: "app.sqlite")
    }

    /// Start StorageKit with just a file name
    /// - Parameter fileName: Database file name (default: "app.sqlite")
    /// - Returns: Configured storage context with kv_cache table ready
    public static func start(fileName: String) throws -> Context {
        try start(fileName: fileName, cacheTTL: .default, diskQuota: .default) { schema in
            schema.addKVCache()
        }
    }

    /// Start StorageKit with minimal configuration
    /// - Parameters:
    ///   - fileName: Database file name (default: "app.sqlite")
    ///   - cacheTTL: Cache time-to-live (default: 5 minutes)
    ///   - diskQuota: Maximum disk cache size (default: 30 MB)
    ///   - migrations: Migration builder closure
    /// - Returns: Configured storage context
    public static func start(
        fileName: String = "app.sqlite",
        cacheTTL: CacheDuration = .default,
        diskQuota: DiskQuota = .default,
        migrations: (inout AppMigrations) -> Void
    ) throws -> Context {
        let url = try defaultDatabaseURL(fileName: fileName)
        return try start(at: url, cacheTTL: cacheTTL, diskQuota: diskQuota, migrations: migrations)
    }

    /// Start StorageKit at specific URL
    public static func start(
        at url: URL,
        cacheTTL: CacheDuration = .default,
        diskQuota: DiskQuota = .default,
        migrations: (inout AppMigrations) -> Void
    ) throws -> Context {
        var schema = AppMigrations()
        migrations(&schema)

        let pool = try makePoolWithDefaults(at: url)
        try schema.run(on: pool)

        let storage = StorageContext(pool: pool, dbActor: DatabaseActor(pool: pool))
        let config = StorageConfig(
            defaultTTL: cacheTTL.seconds,
            diskQuotaBytes: diskQuota.bytes,
            clock: SystemClock(),
            namespace: url.deletingPathExtension().lastPathComponent
        )
        let keys = KeyBuilder(namespace: config.namespace)
        return Context(storage: storage, config: config, keys: keys)
    }

    /// Create database pool with sensible defaults (WAL mode, foreign keys enabled)
    private static func makePoolWithDefaults(at url: URL) throws -> DatabasePool {
        var cfg = Configuration()
        cfg.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        return try DatabasePool(path: url.path, configuration: cfg)
    }

    public static func defaultDatabaseURL(fileName: String = "app.sqlite") throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent(fileName)
    }

}
