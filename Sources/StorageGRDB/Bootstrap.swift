import Foundation
@preconcurrency import GRDB

public enum PoolPreset: Sendable {
    case `default`          // FK + WAL
    case custom([String])
}

public struct PoolOptions: Sendable {
    public enum PragmasPlacement: Sendable { case append, prepend }
    public var preset: PoolPreset
    public var pragmasPlacement: PragmasPlacement
    public var configure: (@Sendable (inout Configuration) -> Void)?

    public init(
        preset: PoolPreset = .default,
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

public enum Bootstrap {
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
