import Foundation

/// Product name and version as declared in the app bundle's Info.plist.
///
/// The values come from `project.yml` build settings, so renaming the product never touches source code.
struct BundleMetadata {
    let displayName: String
    let version: String?

    init(bundle: Bundle) {
        displayName =
            Self.string(for: "CFBundleDisplayName", in: bundle)
            ?? Self.string(for: "CFBundleName", in: bundle)
            ?? ProcessInfo.processInfo.processName
        version = Self.string(for: "CFBundleShortVersionString", in: bundle)
    }

    private static func string(for key: String, in bundle: Bundle) -> String? {
        bundle.object(forInfoDictionaryKey: key) as? String
    }
}
