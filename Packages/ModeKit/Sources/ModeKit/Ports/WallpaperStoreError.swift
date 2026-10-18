/// A failure of ``WallpaperStoreInspector``.
public enum WallpaperStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The data is not a wallpaper store the inspector understands, for example after a macOS format change.
    case unrecognizedFormat(reason: String)

    public var description: String {
        switch self {
        case .unrecognizedFormat(let reason): "Wallpaper store format not recognized: \(reason)"
        }
    }
}
