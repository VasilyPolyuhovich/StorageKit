import Foundation
@preconcurrency import GRDB
import StorageCore
import StorageGRDB
import StorageRepo

public enum StorageKit {

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

    public struct Context {
        public let storage: StorageContext
        public let config: StorageConfig
        public let keys: KeyBuilder

        public init(storage: StorageContext, config: StorageConfig, keys: KeyBuilder) {
            self.storage = storage; self.config = config; self.keys = keys
        }

        public func makeRepository<E: StorageKitEntity, R: StorageKitEntityRecord>(_: E.Type, record _: R.Type) -> GenericRepository<E, R> where R.E == E {
            let ram = MemoryCache<String, E>(capacity: 1000, defaultTTL: config.defaultTTL, clock: config.clock)
            let disk = DiskCache<E>(db: storage.dbActor, config: config)
            return GenericRepository<E, R>(db: storage.dbActor, ram: ram, disk: disk, keys: keys, config: config)
        }
    }

    public static func start(_ options: Options = .init(), migrationsBuilder: (inout AppMigrations) -> Void) throws -> Context {
        let url = try defaultDatabaseURL(fileName: options.fileName)
        return try start(at: url, options: options, migrationsBuilder: migrationsBuilder)
    }

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
