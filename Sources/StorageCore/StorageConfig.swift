import Foundation

public struct StorageConfig: Sendable {
    public var defaultTTL: TimeInterval
    public var diskQuotaBytes: Int
    public var makeEncoder: @Sendable () -> JSONEncoder
    public var makeDecoder: @Sendable () -> JSONDecoder
    public var clock: Clock
    public var namespace: String

    public init(
        defaultTTL: TimeInterval = 300,
        diskQuotaBytes: Int = 20 * 1024 * 1024,
        clock: Clock = SystemClock(),
        namespace: String = "storage",
        configureEncoder: (@Sendable (inout JSONEncoder) -> Void)? = nil,
        configureDecoder: (@Sendable (inout JSONDecoder) -> Void)? = nil
    ) {
        self.defaultTTL = defaultTTL
        self.diskQuotaBytes = diskQuotaBytes
        self.clock = clock
        self.namespace = namespace

        self.makeEncoder = {
            var e = JSONEncoder()
            e.dateEncodingStrategy = .iso8601
            configureEncoder?(&e)
            return e
        }
        self.makeDecoder = {
            var d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            configureDecoder?(&d)
            return d
        }
    }
}
