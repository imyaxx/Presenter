import Foundation

/// A named set of steps that one trigger applies and a second trigger restores.
///
/// The order of ``steps`` is the apply order. A `Profile` value is not validated on construction;
/// ``ProfileValidation/validate(_:)`` checks it and returns it with a trimmed name, and the stores validate
/// every profile they read or write.
///
/// JSON keys: `id`, `name`, `steps`, and `autoExitSeconds` (omitted when ``autoExit`` is nil).
public struct Profile: Codable, Hashable, Identifiable, Sendable {
    /// Stable identity, unique within the profiles file.
    public let id: UUID
    /// Display name; 1 to 60 characters after trimming once validated.
    public let name: String
    /// The steps in apply order.
    public let steps: [ProfileStep]
    /// Time after which the session ends by itself; nil means off.
    public let autoExit: AutoExit?

    /// Creates a profile without validating it.
    public init(id: UUID, name: String, steps: [ProfileStep], autoExit: AutoExit?) {
        self.id = id
        self.name = name
        self.steps = steps
        self.autoExit = autoExit
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, steps
        case autoExit = "autoExitSeconds"
    }
}
