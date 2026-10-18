/// One action in a profile. Each kind may appear at most once per profile (``ProfileValidation``).
///
/// JSON: an object with a `type` discriminator (`hideDesktopIcons`, `hideDock`, `hideMenuBar`, `hideApps`,
/// `wallpaper`) plus the case's fields. `exclusions` is a sorted array. Decoding an unknown `type` fails.
public enum ProfileStep: Codable, Hashable, Sendable {
    case hideDesktopIcons
    case hideDock
    case hideMenuBar
    case hideApps(exclusions: Set<BundleIdentifier>)
    case wallpaper(WallpaperChoice, displays: DisplaySelection)

    /// The action this step drives.
    public var actionIdentifier: ActionIdentifier {
        switch self {
        case .hideDesktopIcons: .desktopIcons
        case .hideDock: .dock
        case .hideMenuBar: .menuBar
        case .hideApps: .hideApps
        case .wallpaper: .wallpaper
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, exclusions, choice, displays
    }

    private enum Kind: String, Codable {
        case hideDesktopIcons, hideDock, hideMenuBar, hideApps, wallpaper
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .hideDesktopIcons:
            self = .hideDesktopIcons
        case .hideDock:
            self = .hideDock
        case .hideMenuBar:
            self = .hideMenuBar
        case .hideApps:
            self = .hideApps(exclusions: Set(try container.decode([BundleIdentifier].self, forKey: .exclusions)))
        case .wallpaper:
            self = .wallpaper(
                try container.decode(WallpaperChoice.self, forKey: .choice),
                displays: try container.decode(DisplaySelection.self, forKey: .displays),
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hideDesktopIcons:
            try container.encode(Kind.hideDesktopIcons, forKey: .type)
        case .hideDock:
            try container.encode(Kind.hideDock, forKey: .type)
        case .hideMenuBar:
            try container.encode(Kind.hideMenuBar, forKey: .type)
        case .hideApps(let exclusions):
            try container.encode(Kind.hideApps, forKey: .type)
            try container.encode(exclusions.sorted(), forKey: .exclusions)
        case .wallpaper(let choice, let displays):
            try container.encode(Kind.wallpaper, forKey: .type)
            try container.encode(choice, forKey: .choice)
            try container.encode(displays, forKey: .displays)
        }
    }
}
