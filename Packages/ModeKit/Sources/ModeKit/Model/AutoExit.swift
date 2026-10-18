/// Time after which an active session ends by itself, in whole seconds.
///
/// Persisted as a plain integer under the profile key `autoExitSeconds`. Decoding a value outside
/// ``ProfileValidation/autoExitSecondsRange`` fails.
public struct AutoExit: Codable, Hashable, Sendable {
    /// Whole seconds, within ``ProfileValidation/autoExitSecondsRange``.
    public let seconds: Int

    /// The same time as a `Duration`, for timers.
    public var duration: Duration {
        .seconds(seconds)
    }

    /// Creates an auto-exit time after validating it.
    ///
    /// - Throws: ``ProfileValidationError/autoExitOutOfRange(seconds:)``.
    public init(seconds: Int) throws(ProfileValidationError) {
        try ProfileValidation.validateAutoExitSeconds(seconds)
        self.seconds = seconds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Int.self)
        do {
            try self.init(seconds: value)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Auto-exit out of range")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(seconds)
    }
}
