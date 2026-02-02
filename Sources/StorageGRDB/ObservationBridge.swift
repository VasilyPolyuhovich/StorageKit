import Foundation
@preconcurrency import GRDB

/// Bridge between GRDB ValueObservation and Swift async/await patterns.
///
/// Uses GRDB 7+ native AsyncSequence support for observations.
public enum ObservationBridge {

    /// Error handler type for observation errors.
    public typealias ErrorHandler = @Sendable (Error) -> Void

    // MARK: - AsyncStream wrappers

    /// Stream values with immediate delivery (background thread).
    public static func stream<T: Sendable>(
        reader: some DatabaseReader,
        bufferingPolicy: AsyncStream<T>.Continuation.BufferingPolicy = .bufferingNewest(1),
        onError: ErrorHandler? = nil,
        tracking: @escaping @Sendable (Database) throws -> T
    ) -> AsyncStream<T> {
        AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            let task = Task {
                do {
                    for try await value in ValueObservation.tracking(tracking).values(in: reader) {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    onError?(error)
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Stream values with MainActor delivery for UI-safe updates.
    ///
    /// Values are yielded on MainActor, making it safe to update SwiftUI views directly.
    public static func streamOnMainActor<T: Sendable>(
        reader: some DatabaseReader,
        bufferingPolicy: AsyncStream<T>.Continuation.BufferingPolicy = .bufferingNewest(1),
        onError: ErrorHandler? = nil,
        tracking: @escaping @Sendable (Database) throws -> T
    ) -> AsyncStream<T> {
        AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            let task = Task {
                do {
                    for try await value in ValueObservation.tracking(tracking).values(in: reader) {
                        _ = await MainActor.run {
                            continuation.yield(value)
                        }
                    }
                    _ = await MainActor.run { continuation.finish() }
                } catch {
                    onError?(error)
                    _ = await MainActor.run { continuation.finish() }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Stream distinct values (skips duplicates) with MainActor delivery.
    ///
    /// Only yields when the value changes, reducing unnecessary UI updates.
    public static func streamDistinctOnMainActor<T: Sendable & Equatable>(
        reader: some DatabaseReader,
        bufferingPolicy: AsyncStream<T>.Continuation.BufferingPolicy = .bufferingNewest(1),
        onError: ErrorHandler? = nil,
        tracking: @escaping @Sendable (Database) throws -> T
    ) -> AsyncStream<T> {
        AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            let task = Task {
                var last: T?
                do {
                    for try await value in ValueObservation.tracking(tracking).values(in: reader) {
                        if last != value {
                            last = value
                            _ = await MainActor.run {
                                continuation.yield(value)
                            }
                        }
                    }
                    _ = await MainActor.run { continuation.finish() }
                } catch {
                    onError?(error)
                    _ = await MainActor.run { continuation.finish() }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
