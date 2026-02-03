import Foundation
@preconcurrency import GRDB

public actor DatabaseActor {
    private let pool: DatabasePool

    public init(pool: DatabasePool) { self.pool = pool }

    /// Read from database using GRDB's native async API
    public func read<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        try await pool.read { db in try block(db) }
    }

    /// Write to database using GRDB's native async API
    public func write<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        try await pool.write { db in try block(db) }
    }

    // MARK: - Observation Streams

    /// Stream with immediate delivery (background thread).
    nonisolated public func stream<T: Sendable>(
        bufferingPolicy: AsyncStream<T>.Continuation.BufferingPolicy = .bufferingNewest(1),
        tracking: @escaping @Sendable (Database) throws -> T
    ) -> AsyncStream<T> {
        ObservationBridge.stream(reader: pool, bufferingPolicy: bufferingPolicy, tracking: tracking)
    }

    /// Stream with MainActor delivery for UI-safe updates.
    nonisolated public func streamOnMainActor<T: Sendable>(
        bufferingPolicy: AsyncStream<T>.Continuation.BufferingPolicy = .bufferingNewest(1),
        tracking: @escaping @Sendable (Database) throws -> T
    ) -> AsyncStream<T> {
        ObservationBridge.streamOnMainActor(reader: pool, bufferingPolicy: bufferingPolicy, tracking: tracking)
    }

    /// Stream distinct values with MainActor delivery (skips duplicates).
    nonisolated public func streamDistinctOnMainActor<T: Sendable & Equatable>(
        bufferingPolicy: AsyncStream<T>.Continuation.BufferingPolicy = .bufferingNewest(1),
        tracking: @escaping @Sendable (Database) throws -> T
    ) -> AsyncStream<T> {
        ObservationBridge.streamDistinctOnMainActor(reader: pool, bufferingPolicy: bufferingPolicy, tracking: tracking)
    }

    /// Access the underlying DatabasePool (for advanced use cases).
    nonisolated public func reader() -> DatabasePool { pool }
}
