// Writes a sanitized copy of a wallpaper store (Index.plist) for use as a test fixture (ADR-041).
//
// Usage: swift Scripts/sanitize-wallpaper-store.swift <input Index.plist> <output .plist>
//
// Keeps the structure, provider names, configuration types and color values. Replaces every UUID (keys and values)
// with 00000000-0000-0000-0000-<n>, every string containing "/" (paths and file URLs) with a placeholder file URL,
// every string containing the user name, and every date with 2026-01-01T00:00:00Z. Nested binary property lists are
// sanitized recursively and re-encoded. Placeholders are numbered in dictionary traversal order, so two runs give
// equivalent but not byte-identical files. Read the output before committing it.
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: sanitize-wallpaper-store.swift <input> <output>\n".utf8))
    exit(2)
}

final class Sanitizer {
    private var uuidPlaceholders: [String: String] = [:]
    private var pathCount = 0
    private let uuidPattern: NSRegularExpression

    init() throws {
        uuidPattern = try NSRegularExpression(
            pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
    }
    private let userName = NSUserName()
    private let fixedDate = Date(timeIntervalSince1970: 1_767_225_600)

    func sanitize(_ value: Any) -> Any {
        switch value {
        case let dictionary as [String: Any]:
            var result: [String: Any] = [:]
            for (key, item) in dictionary {
                result[sanitize(string: key)] = sanitize(item)
            }
            return result
        case let array as [Any]:
            return array.map(sanitize)
        case let string as String:
            return sanitize(string: string)
        case let data as Data:
            return sanitize(data: data)
        case is Date:
            return fixedDate
        default:
            return value
        }
    }

    private func sanitize(string: String) -> String {
        if string.contains("/") {
            pathCount += 1
            return "file:///Placeholder/image-\(pathCount).jpg"
        }
        var result = string
        let range = NSRange(result.startIndex..., in: result)
        for match in uuidPattern.matches(in: result, range: range).reversed() {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            let original = String(result[swiftRange]).uppercased()
            let placeholder = uuidPlaceholders[original] ?? {
                let next = String(format: "00000000-0000-0000-0000-%012d", uuidPlaceholders.count + 1)
                uuidPlaceholders[original] = next
                return next
            }()
            result.replaceSubrange(swiftRange, with: placeholder)
        }
        return result.replacingOccurrences(of: userName, with: "placeholder-user")
    }

    private func sanitize(data: Data) -> Data {
        guard data.starts(with: Data("bplist".utf8)),
            let inner = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let encoded = try? PropertyListSerialization.data(
                fromPropertyList: sanitize(inner), format: .binary, options: 0)
        else {
            return data
        }
        return encoded
    }
}

let input = try Data(contentsOf: URL(filePath: arguments[1]))
let store = try PropertyListSerialization.propertyList(from: input, format: nil)
let output = try PropertyListSerialization.data(
    fromPropertyList: try Sanitizer().sanitize(store), format: .binary, options: 0)
try output.write(to: URL(filePath: arguments[2]))
