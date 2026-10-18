/// AppleScript source that can only come from a compile-time literal (`StaticString`): no interpolation, so no
/// value can be injected into a script (ADR-034).
public struct AppleScript: Hashable, Sendable {
    /// The script source.
    public let source: String

    /// Creates a script from a literal.
    public init(_ source: StaticString) {
        self.source = source.description
    }
}
