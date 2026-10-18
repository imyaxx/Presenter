/// An application bundle identifier that passed ``ProfileValidation/validateBundleIdentifier(_:)``.
///
/// Persisted as a plain string. Decoding a value that breaks the rule fails.
public struct BundleIdentifier: Codable, Hashable, Sendable, Comparable {
    /// The validated identifier, for example `com.apple.Safari`.
    public let rawValue: String

    /// Creates a bundle identifier after validating it.
    ///
    /// - Throws: ``ProfileValidationError/invalidBundleIdentifier(_:)``.
    public init(_ rawValue: String) throws(ProfileValidationError) {
        try ProfileValidation.validateBundleIdentifier(rawValue)
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            try self.init(value)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid bundle identifier")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: BundleIdentifier, rhs: BundleIdentifier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
