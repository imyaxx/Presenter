import Foundation
import ModeKit

/// A ``SolidColorImageRenderer`` that records colors and returns deterministic bytes (not a real PNG), or a scripted
/// error.
actor FakeSolidColorImageRenderer: SolidColorImageRenderer {
    private(set) var colors: [SolidColor] = []
    private var failure: (any Error)?

    /// The bytes returned for `color`: the PNG signature's first four bytes followed by the three channels.
    static func bytes(for color: SolidColor) -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, color.red, color.green, color.blue])
    }

    func fail(with error: any Error) {
        failure = error
    }

    func pngData(for color: SolidColor) async throws -> Data {
        colors.append(color)
        if let failure {
            throw failure
        }
        return Self.bytes(for: color)
    }
}
