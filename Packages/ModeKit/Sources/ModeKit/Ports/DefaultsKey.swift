/// A preference key in a preferences domain, for example `com.apple.dock` / `autohide`.
public struct DefaultsKey: Hashable, Sendable, CustomStringConvertible {
    /// The preferences domain.
    public let domain: String
    /// The key within the domain.
    public let name: String

    /// Creates a key.
    public init(domain: String, name: String) {
        self.domain = domain
        self.name = name
    }

    public var description: String {
        "\(domain) \(name)"
    }
}
