import Foundation
import Testing

@testable import PresenterApp

/// Creates folders under a temporary base only; never opens Finder.
struct NSWorkspaceProfilesFolderRevealerTests {
    @Test
    func theFolderIsCreatedWithItsParentsAndAnExistingOneIsKept() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "presenter-reveal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let folder = base.appending(path: "Application Support/dev.example.app", directoryHint: .isDirectory)
        let revealer = NSWorkspaceProfilesFolderRevealer(directory: folder)
        let marker = folder.appending(path: "profiles.json")

        try revealer.createDirectoryIfMissing()
        try Data("{}".utf8).write(to: marker)
        try revealer.createDirectoryIfMissing()

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }
}
