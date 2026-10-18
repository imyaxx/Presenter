import ModeKit

/// A failure of ``AppKitWorkspaceAdapter/setDesktopImage(_:on:)``, raised before the system is asked.
enum WorkspaceError: Error, Equatable, Sendable, CustomStringConvertible {
    /// No connected screen has this display UUID.
    case displayNotFound(DisplayIdentifier)
    /// The image file does not exist. Carries the file name only, never the path.
    case imageNotFound(fileName: String)

    var description: String {
        switch self {
        case .displayNotFound(let display): "No connected display \(display.uuid.uuidString)"
        case .imageNotFound(let fileName): "Desktop image not found: \(fileName)"
        }
    }
}
