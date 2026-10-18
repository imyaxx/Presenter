/// A failure of a ``DefaultsStore``.
public enum DefaultsError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The stored value has a type ``DefaultsValue`` does not model.
    case unsupportedValueType(DefaultsKey)
    /// Reading, writing or removing failed.
    case failed(reason: String)

    public var description: String {
        switch self {
        case .unsupportedValueType(let key): "Unsupported value type for \(key)"
        case .failed(let reason): "Preferences access failed: \(reason)"
        }
    }
}
