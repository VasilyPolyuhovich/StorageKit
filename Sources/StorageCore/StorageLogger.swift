import Foundation
import os.log

/// Logging levels for StorageKit
public enum StorageLogLevel: Int, Sendable, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case none = 4

    public static func < (lhs: StorageLogLevel, rhs: StorageLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .none: return .info
        }
    }
}

/// Custom log handler type
public typealias StorageLogHandler = @Sendable (StorageLogLevel, String, String, Int) -> Void

/// Configurable logger for StorageKit operations
public final class StorageLogger: Sendable {
    /// Shared logger instance
    public static let shared = StorageLogger()

    private let osLog: OSLog
    private let _level: OSAllocatedUnfairLock<StorageLogLevel>
    private let _handler: OSAllocatedUnfairLock<StorageLogHandler?>

    /// Current log level (messages below this level are ignored)
    public var level: StorageLogLevel {
        get { _level.withLock { $0 } }
        set { _level.withLock { $0 = newValue } }
    }

    /// Custom log handler (if nil, uses os.log)
    public var handler: StorageLogHandler? {
        get { _handler.withLock { $0 } }
        set { _handler.withLock { $0 = newValue } }
    }

    private init() {
        self.osLog = OSLog(subsystem: "com.storagekit", category: "Storage")
        self._level = OSAllocatedUnfairLock(initialState: .warning)
        self._handler = OSAllocatedUnfairLock(initialState: nil)
    }

    /// Set the minimum log level
    public func setLevel(_ level: StorageLogLevel) {
        self.level = level
    }

    /// Set a custom log handler
    public func setHandler(_ handler: @escaping StorageLogHandler) {
        self.handler = handler
    }

    /// Remove custom handler (reverts to os.log)
    public func removeHandler() {
        self.handler = nil
    }

    /// Log a message at the specified level
    public func log(
        _ logLevel: StorageLogLevel,
        _ message: @autoclosure () -> String,
        file: String = #file,
        line: Int = #line
    ) {
        guard logLevel >= level else { return }

        let msg = message()
        let filename = (file as NSString).lastPathComponent

        if let customHandler = handler {
            customHandler(logLevel, msg, filename, line)
        } else {
            os_log("%{public}@", log: osLog, type: logLevel.osLogType, "[\(filename):\(line)] \(msg)")
        }
    }

    // MARK: - Convenience Methods

    /// Log a debug message
    public func debug(_ message: @autoclosure () -> String, file: String = #file, line: Int = #line) {
        log(.debug, message(), file: file, line: line)
    }

    /// Log an info message
    public func info(_ message: @autoclosure () -> String, file: String = #file, line: Int = #line) {
        log(.info, message(), file: file, line: line)
    }

    /// Log a warning message
    public func warning(_ message: @autoclosure () -> String, file: String = #file, line: Int = #line) {
        log(.warning, message(), file: file, line: line)
    }

    /// Log an error message
    public func error(_ message: @autoclosure () -> String, file: String = #file, line: Int = #line) {
        log(.error, message(), file: file, line: line)
    }

    /// Log an error with the underlying Error object
    public func error(_ message: @autoclosure () -> String, error: Error, file: String = #file, line: Int = #line) {
        log(.error, "\(message()): \(error.localizedDescription)", file: file, line: line)
    }
}

// MARK: - Global Convenience Functions

/// Log to StorageKit's shared logger
public func storageLog(
    _ level: StorageLogLevel,
    _ message: @autoclosure () -> String,
    file: String = #file,
    line: Int = #line
) {
    StorageLogger.shared.log(level, message(), file: file, line: line)
}
