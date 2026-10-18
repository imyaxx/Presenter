/// An opaque 8-bit sRGB color for a generated solid-color wallpaper.
public struct SolidColor: Codable, Hashable, Sendable {
    /// Red channel, 0 to 255.
    public let red: UInt8
    /// Green channel, 0 to 255.
    public let green: UInt8
    /// Blue channel, 0 to 255.
    public let blue: UInt8

    /// Creates a color from its three channels.
    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}
