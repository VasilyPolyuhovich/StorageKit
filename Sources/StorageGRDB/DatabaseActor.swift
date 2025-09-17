import Foundation
@preconcurrency import GRDB

public actor DatabaseActor {
    private let pool: DatabasePool

    public init(pool: DatabasePool) { self.pool = pool }

    public func read<T>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            do {
                let value = try pool.read { db in
                    try block(db)
                }
                cont.resume(returning: value)
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
    
    public func write<T>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            do {
                let value = try pool.write { db in
                    try block(db)
                }
                cont.resume(returning: value)
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    /// Stream with .immediate scheduling; emits on whatever thread GRDB uses.
    public func stream<T: Sendable>(
        bufferingPolicy: AsyncStream<T>.Continuation.BufferingPolicy = .bufferingNewest(1),
        tracking: @escaping @Sendable (Database) throws -> T
    ) -> AsyncStream<T> {
        ObservationBridge.stream(reader: pool, bufferingPolicy: bufferingPolicy, tracking: tracking)
    }
    
    public func streamOnMainActor<T: Sendable>(
        bufferingPolicy: AsyncStream<T>.Continuation.BufferingPolicy = .bufferingNewest(1),
        tracking: @escaping @Sendable (Database) throws -> T
    ) -> AsyncStream<T> {
        ObservationBridge.streamOnMainActor(reader: pool, bufferingPolicy: bufferingPolicy, tracking: tracking)
    }
    
    public func streamDistinctOnMainActor<T: Sendable & Equatable>(
        bufferingPolicy: AsyncStream<T>.Continuation.BufferingPolicy = .bufferingNewest(1),
        tracking: @escaping @Sendable (Database) throws -> T
    ) -> AsyncStream<T> {
        ObservationBridge.streamDistinctOnMainActor(reader: pool, bufferingPolicy: bufferingPolicy, tracking: tracking)
    }
        
    public func reader() -> DatabasePool { pool }
}
