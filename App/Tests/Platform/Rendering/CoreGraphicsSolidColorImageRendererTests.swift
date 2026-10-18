import CoreGraphics
import Foundation
import ImageIO
import ModeKit
import Testing

@testable import PresenterApp

struct CoreGraphicsSolidColorImageRendererTests {
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    @Test(arguments: [
        SolidColor(red: 0, green: 0, blue: 0),
        SolidColor(red: 255, green: 255, blue: 255),
        SolidColor(red: 255, green: 0, blue: 0),
        SolidColor(red: 0, green: 255, blue: 0),
        SolidColor(red: 0, green: 0, blue: 255),
        SolidColor(red: 0x15, green: 0x15, blue: 0x15),
        SolidColor(red: 0x1E, green: 0x90, blue: 0xFF),
    ])
    func theImageIsA64PixelPNGFilledWithTheExactColor(color: SolidColor) async throws {
        let png = try await CoreGraphicsSolidColorImageRenderer().pngData(for: color)

        #expect(png.starts(with: Self.pngSignature))
        let image = try #require(Self.decode(png))
        #expect(image.width == 64)
        #expect(image.height == 64)
        let corner = try #require(Self.pixel(of: image, column: 0, row: 0))
        let center = try #require(Self.pixel(of: image, column: 32, row: 32))
        #expect(corner == [color.red, color.green, color.blue, 255])
        #expect(center == corner)
    }

    private static func decode(_ png: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Draws the image into an RGBA sRGB bitmap and returns the four bytes of one pixel.
    private static func pixel(of image: CGImage, column: Int, row: Int) -> [UInt8]? {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
                )
            else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return nil
        }
        let offset = (row * width + column) * 4
        return Array(bytes[offset..<offset + 4])
    }
}
