import Foundation
@preconcurrency import GRDB
import StorageCore
import StorageGRDB
import StorageRepo

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

    // MARK: - Legacy Configuration (deprecated)

    @available(*, deprecated, message: "Use simplified start() API instead")
    public struct PoolOptions: Sendable {
        public enum PragmasPlacement: Sendable { case append, prepend }
        public enum Preset: Sendable { case `default`, custom([String]) }

        public var preset: Preset
        public var pragmasPlacement: PragmasPlacement
        public var configure: (@Sendable (inout Configuration) -> Void)?

        public init(
            preset: Preset = .default,
            pragmasPlacement: PragmasPlacement = .append,
            configure: (@Sendable (inout Configuration) -> Void)? = nil
        ) {
            self.preset = preset
            self.pragmasPlacement = pragmasPlacement
            self.configure = configure
        }

        public var pragmas: [String] {
            switch preset {
            case .default: return ["PRAGMA foreign_keys = ON", "PRAGMA journal_mode = WAL"]
            case .custom(let list): return list
            }
        }
    }

    @available(*, deprecated, message: "Use simplified start() API instead")
    public struct Options: Sendable {
        public var fileName: String
        public var namespace: String
        public var defaultTTL: TimeInterval
        public var diskQuotaBytes: Int
        public var pool: PoolOptions

        public init(
            fileName: String = "app.sqlite",
            namespace: String = "app",
            defaultTTL: TimeInterval = 300,
            diskQuotaBytes: Int = 30 * 1024 * 1024,
            pool: PoolOptions = .init()
        ) {
            self.fileName = fileName
            self.namespace = namespace
            self.defaultTTL = defaultTTL
            self.diskQuotaBytes = diskQuotaBytes
            self.pool = pool
        }
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

    // MARK: - Legacy Start API (deprecated)

    @available(*, deprecated, message: "Use start(fileName:cacheTTL:diskQuota:migrations:) instead")
    public static func start(_ options: Options = .init(), migrationsBuilder: (inout AppMigrations) -> Void) throws -> Context {
        let url = try defaultDatabaseURL(fileName: options.fileName)
        return try start(at: url, options: options, migrationsBuilder: migrationsBuilder)
    }

    @available(*, deprecated, message: "Use start(at:cacheTTL:diskQuota:migrations:) instead")
    public static func start(at url: URL, options: Options = .init(), migrationsBuilder: (inout AppMigrations) -> Void) throws -> Context {
        var schema = AppMigrations()
        migrationsBuilder(&schema)

        let pool = try makePool(at: url, options: options.pool)
        try schema.run(on: pool)

        let storage = StorageContext(pool: pool, dbActor: DatabaseActor(pool: pool))
        let config = StorageConfig(defaultTTL: options.defaultTTL, diskQuotaBytes: options.diskQuotaBytes, clock: SystemClock(), namespace: options.namespace)
        let keys = KeyBuilder(namespace: config.namespace)
        return Context(storage: storage, config: config, keys: keys)
    }

    @available(*, deprecated, message: "Internal API - will be removed in future versions")
    public static func makePool(at url: URL, options: PoolOptions = .init()) throws -> DatabasePool {
        var cfg = Configuration()
        switch options.pragmasPlacement {
        case .prepend:
            let pragmas = options.pragmas
            if !pragmas.isEmpty {
                cfg.prepareDatabase { db in
                    for sql in pragmas { try db.execute(sql: sql) }
                }
            }
            if let hook = options.configure { hook(&cfg) }
        case .append:
            if let hook = options.configure { hook(&cfg) }
            let pragmas = options.pragmas
            if !pragmas.isEmpty {
                cfg.prepareDatabase { db in
                    for sql in pragmas { try db.execute(sql: sql) }
                }
            }
        }
        return try DatabasePool(path: url.path, configuration: cfg)
    }

    public static func defaultDatabaseURL(fileName: String = "app.sqlite") throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent(fileName)
    }
}
