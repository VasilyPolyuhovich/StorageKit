import Foundation

public actor MemoryCache<Key: Hashable & Sendable, Value: Sendable> {
    public let capacity: Int
    public let defaultTTL: TimeInterval
    public let clock: Clock

    private struct Entry {
        var value: Value
        var expiresAt: Date?
        var lastAccess: UInt64
    }

    private var storage: [Key: Entry] = [:]
    private var tick: UInt64 = 0

    public init(capacity: Int, defaultTTL: TimeInterval, clock: Clock) {
        precondition(capacity > 0, "capacity must be > 0")
        self.capacity = capacity
        self.defaultTTL = defaultTTL
        self.clock = clock
    }

    public func get(_ key: Key) -> Value? {
        guard var e = storage[key] else { return nil }
        if let exp = e.expiresAt, exp <= clock.now {
            storage.removeValue(forKey: key)
            return nil
        }
        tick &+= 1
        e.lastAccess = tick
        storage[key] = e
        return e.value
    }

    public func set(_ value: Value, for key: Key, ttl: TimeInterval?) {
        let ttl = ttl ?? defaultTTL
        let exp: Date? = ttl > 0 ? clock.now.addingTimeInterval(ttl) : nil
        tick &+= 1
        storage[key] = Entry(value: value, expiresAt: exp, lastAccess: tick)
        evictIfNeeded()
    }

    public func remove(_ key: Key) { storage.removeValue(forKey: key) }
    public func removeAll() { storage.removeAll(keepingCapacity: false) }

    private func evictIfNeeded() {
        guard storage.count > capacity else { return }
        let now = clock.now
        for (k, e) in storage where (e.expiresAt?.addingTimeInterval(0) ?? .distantFuture) <= now {
            storage.removeValue(forKey: k)
        }
        guard storage.count > capacity else { return }
        let toRemove = storage.count - capacity
        let sorted = storage.sorted { $0.value.lastAccess < $1.value.lastAccess }
        for i in 0..<toRemove {
            storage.removeValue(forKey: sorted[i].key)
        }
    }
}
