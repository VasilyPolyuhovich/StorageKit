public struct RepoPage<T: Sendable>: Sendable {
    public let items: [T]
    public let nextOffset: Int
    public let hasMore: Bool
    public init(items: [T], nextOffset: Int, hasMore: Bool) {
        self.items = items
        self.nextOffset = nextOffset
        self.hasMore = hasMore
    }
}
