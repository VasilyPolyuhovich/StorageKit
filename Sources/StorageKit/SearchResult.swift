import Foundation
import StorageGRDB

/// Result from full-text search with ranking information.
///
/// Usage:
/// ```swift
/// let results = try await storage.search(Article.self, query: "swift performance")
/// for result in results {
///     print("\(result.entity.title) - rank: \(result.rank)")
/// }
/// ```
public struct SearchResult<E: RegisteredEntity>: Sendable {
    /// The matched entity
    public let entity: E

    /// BM25 ranking score (lower = better match)
    public let rank: Double

    /// Optional snippet with highlighted match context
    public let snippet: String?

    public init(entity: E, rank: Double, snippet: String? = nil) {
        self.entity = entity
        self.rank = rank
        self.snippet = snippet
    }
}

extension SearchResult: Equatable where E: Equatable {}
