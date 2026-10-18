/// A failure of ``CoreGraphicsSolidColorImageRenderer``.
enum RenderingError: Error, Equatable, Sendable {
    /// The sRGB bitmap context or its image could not be created.
    case bitmapUnavailable
    /// ImageIO did not produce PNG data.
    case encodingFailed
}
