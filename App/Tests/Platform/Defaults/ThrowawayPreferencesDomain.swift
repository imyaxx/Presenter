import CoreFoundation
import Foundation
import ModeKit

/// A preferences domain that exists only for one test suite run: `dev.imyaxx.presenter.tests.<UUID>`. ``delete()``
/// removes every key and the domain's plist file.
final class ThrowawayPreferencesDomain: Sendable {
    /// The domain of ``CFPreferencesDefaultsStoreTests``, deleted after that suite.
    static let defaultsStoreSuite = ThrowawayPreferencesDomain()

    let name = "dev.imyaxx.presenter.tests.\(UUID().uuidString)"

    /// A key unique to the calling test case: `<label>-<UUID>`, so tests sharing the domain never collide.
    func key(_ label: String) -> DefaultsKey {
        DefaultsKey(domain: name, name: "\(label)-\(UUID().uuidString)")
    }

    /// Writes a value of any property-list type, bypassing the store under test.
    func writeDirectly(_ value: CFPropertyList, for key: DefaultsKey) {
        let application = name as CFString
        let keyName = key.name as CFString
        CFPreferencesSetValue(keyName, value, application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    /// Removes every key, then the plist file.
    ///
    /// Machine-observed on macOS 27.0 (2026-10-18): after the last key of a domain is removed and synchronized,
    /// cfprefsd rewrites the domain's file once, as an empty dictionary, about 10 s later, and then leaves it alone.
    /// So when the file exists, it is removed, the rewrite is awaited for up to ``rewriteLimit``, and removed again.
    func delete() async {
        let application = name as CFString
        CFPreferencesSynchronize(application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let keys = CFPreferencesCopyKeyList(application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]
        for key in keys ?? [] {
            CFPreferencesSetValue(key as CFString, nil, application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        CFPreferencesSynchronize(application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard removeFile() else {
            return
        }
        let clock = ContinuousClock()
        let deadline = clock.now + Self.rewriteLimit
        while clock.now < deadline, !removeFile() {
            // Cleanup must finish even when the test was cancelled, so a cancelled sleep only shortens one poll.
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    private static let pollInterval = Duration.milliseconds(200)
    private static let rewriteLimit = Duration.seconds(15)

    /// Removes the domain's file if it exists. Returns whether there was a file.
    private func removeFile() -> Bool {
        let file = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Preferences/\(name).plist")
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else {
            return false
        }
        // A failed removal leaves an empty test domain file behind; it is reported by the next existence check.
        try? FileManager.default.removeItem(at: file)
        return true
    }
}
