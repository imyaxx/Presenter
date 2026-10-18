import Foundation

/// Renders a solid color as PNG data for a generated wallpaper. ModeKit has no image framework; the adapter renders.
///
/// Threading: implementations are `Sendable`.
public protocol SolidColorImageRenderer: Sendable {
    /// Returns PNG data of an opaque image filled with `color`.
    ///
    /// - Throws: An error of the rendering mechanism.
    func pngData(for color: SolidColor) async throws -> Data
}
