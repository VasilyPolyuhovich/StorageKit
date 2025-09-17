import Foundation
@preconcurrency import GRDB

public enum ObservationBridge {
    
    public static func stream<T: Sendable>(
        reader: any DatabaseReader,
        bufferingPolicy: AsyncStream<T>.Continuation.BufferingPolicy = .bufferingNewest(1),
        tracking: @escaping @Sendable (Database) throws -> T
    ) -> AsyncStream<T> {
        let sequence = ValueObservation.tracking(tracking).values(in: reader)
        
        return AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            let task = Task {
                do {
                    for try await value in sequence {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    
    public static func streamOnMainActor<T: Sendable>(
        reader: any DatabaseReader,
        bufferingPolicy: AsyncStream<T>.Continuation.BufferingPolicy = .bufferingNewest(1),
        tracking: @escaping @Sendable (Database) throws -> T
    ) -> AsyncStream<T> {
        let sequence = ValueObservation.tracking(tracking).values(in: reader)
        
        return AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            let task = Task {
                do {
                    for try await value in sequence {
                        await MainActor.run { _ = continuation.yield(value) } 
                    }
                    await MainActor.run { continuation.finish() }
                } catch {
                    await MainActor.run { continuation.finish() }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    
    public static func streamDistinctOnMainActor<T: Sendable & Equatable>(
        reader: any DatabaseReader,
        bufferingPolicy: AsyncStream<T>.Continuation.BufferingPolicy = .bufferingNewest(1),
        tracking: @escaping @Sendable (Database) throws -> T
    ) -> AsyncStream<T> {
        let sequence = ValueObservation.tracking(tracking).values(in: reader)
        
        return AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            let task = Task {
                var last: T?
                do {
                    for try await value in sequence {
                        if last != value {
                            last = value
                            await MainActor.run { _ = continuation.yield(value) }  // << fix
                        }
                    }
                    await MainActor.run { continuation.finish() }
                } catch {
                    await MainActor.run { continuation.finish() }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
