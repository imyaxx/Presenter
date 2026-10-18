/// Which displays a wallpaper step applies to.
///
/// JSON: `{ "type": "allDisplays" }` or `{ "type": "specific", "displays": ["<uuid>", ...] }` with the
/// identifiers sorted. ``ProfileValidation`` rejects an empty specific selection.
public enum DisplaySelection: Codable, Hashable, Sendable {
    case allDisplays
    case specific(Set<DisplayIdentifier>)

    private enum CodingKeys: String, CodingKey {
        case type, displays
    }

    private enum Kind: String, Codable {
        case allDisplays, specific
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .allDisplays:
            self = .allDisplays
        case .specific:
            self = .specific(Set(try container.decode([DisplayIdentifier].self, forKey: .displays)))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allDisplays:
            try container.encode(Kind.allDisplays, forKey: .type)
        case .specific(let displays):
            try container.encode(Kind.specific, forKey: .type)
            try container.encode(displays.sorted(), forKey: .displays)
        }
    }
}
