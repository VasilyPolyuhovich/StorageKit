import Foundation

public struct KeyBuilder: Sendable {
    public let namespace: String
    public init(namespace: String) { self.namespace = namespace }

    public func entityKey<T>(_ type: T.Type, id: String) -> String {
        "\(namespace).\(String(describing: T.self)):\(id)"
    }

    public func queryKey(_ name: String, params: [String: String] = [:]) -> String {
        if params.isEmpty { return "\(namespace).query:\(name)" }
        let sorted = params.sorted(by: { $0.key < $1.key })
        let suffix = sorted.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return "\(namespace).query:\(name)?\(suffix)"
    }
}
