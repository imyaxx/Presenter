import AppKit
import CoreGraphics
import ModeKit

/// Maps an `NSScreen` to its display UUID and back: `NSScreenNumber`, then `CGDirectDisplayID`, then
/// `CGDisplayCreateUUIDFromDisplayID`, the key the system itself uses in the wallpaper store (S2).
enum DisplayIdentifierMapping {
    private static let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")

    /// The display UUID of `screen`, or nil when the system reports none.
    @MainActor
    static func identifier(of screen: NSScreen) -> DisplayIdentifier? {
        guard let number = screen.deviceDescription[screenNumberKey] as? NSNumber else {
            return nil
        }
        return identifier(ofDisplay: CGDirectDisplayID(number.uint32Value))
    }

    /// The connected screen with this display UUID.
    @MainActor
    static func screen(for display: DisplayIdentifier) -> NSScreen? {
        NSScreen.screens.first { identifier(of: $0) == display }
    }

    static func identifier(ofDisplay displayID: CGDirectDisplayID) -> DisplayIdentifier? {
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
            let uuid = UUID(uuidString: CFUUIDCreateString(nil, cfUUID) as String)
        else {
            return nil
        }
        return DisplayIdentifier(uuid: uuid)
    }
}
