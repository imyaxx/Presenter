import Foundation

/// What a wallpaper step shows: a generated solid color or an image file.
///
/// JSON: `{ "type": "solidColor", "red": 21, "green": 21, "blue": 21 }` or
/// `{ "type": "image", "path": "/absolute/path.png" }`. The image is stored as an absolute file path;
/// decoding a relative path or an unknown `type` fails.
public enum WallpaperChoice: Codable, Hashable, Sendable {
    case solidColor(SolidColor)
    case image(URL)

    private enum CodingKeys: String, CodingKey {
        case type, red, green, blue, path
    }

    private enum Kind: String, Codable {
        case solidColor, image
    }

    private static let absolutePathPrefix = "/"

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .solidColor:
            self = .solidColor(
                SolidColor(
                    red: try container.decode(UInt8.self, forKey: .red),
                    green: try container.decode(UInt8.self, forKey: .green),
                    blue: try container.decode(UInt8.self, forKey: .blue),
                )
            )
        case .image:
            let path = try container.decode(String.self, forKey: .path)
            guard path.hasPrefix(Self.absolutePathPrefix) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .path,
                    in: container,
                    debugDescription: "Image path must be absolute",
                )
            }
            self = .image(URL(filePath: path))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .solidColor(let color):
            try container.encode(Kind.solidColor, forKey: .type)
            try container.encode(color.red, forKey: .red)
            try container.encode(color.green, forKey: .green)
            try container.encode(color.blue, forKey: .blue)
        case .image(let url):
            try container.encode(Kind.image, forKey: .type)
            try container.encode(url.path(percentEncoded: false), forKey: .path)
        }
    }
}
