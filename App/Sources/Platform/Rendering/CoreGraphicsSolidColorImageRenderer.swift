import CoreGraphics
import Foundation
import ImageIO
import ModeKit
import UniformTypeIdentifiers

/// The real ``SolidColorImageRenderer``: a 64 by 64 pixel opaque sRGB bitmap filled with the color, encoded as PNG with
/// ImageIO (the size spike S2 used).
///
/// Threading: a value type; Core Graphics bitmap contexts and ImageIO are used on the calling thread only.
struct CoreGraphicsSolidColorImageRenderer: SolidColorImageRenderer {
    static let sideLength = 64
    private static let maximumChannelValue = 255.0

    /// - Throws: ``RenderingError``.
    func pngData(for color: SolidColor) async throws -> Data {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: Self.sideLength,
                height: Self.sideLength,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
            ),
            let fill = CGColor(colorSpace: colorSpace, components: Self.components(of: color))
        else {
            throw RenderingError.bitmapUnavailable
        }
        context.setFillColor(fill)
        context.fill(CGRect(x: 0, y: 0, width: Self.sideLength, height: Self.sideLength))
        guard let image = context.makeImage() else {
            throw RenderingError.bitmapUnavailable
        }
        return try Self.png(of: image)
    }

    private static func components(of color: SolidColor) -> [CGFloat] {
        [color.red, color.green, color.blue].map { CGFloat(Double($0) / maximumChannelValue) } + [1]
    }

    private static func png(of image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else {
            throw RenderingError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw RenderingError.encodingFailed
        }
        return output as Data
    }
}
