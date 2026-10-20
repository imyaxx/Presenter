#if DEBUG
import Foundation

/// The shape of a wallpaper store as key names and value kinds, never values (`store-structure`, ADR-041).
///
/// Display and Space UUID keys are collapsed to a count with the shape of the first one; the empty key is shown as
/// `""`. Nested binary property lists are shown as `(nested)` with their own shape.
enum StoreStructure {

    static func lines(of value: PropertyListValue, depth: Int = 0) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        switch value {
        case .dictionary(let dictionary):
            return dictionaryLines(dictionary, depth: depth)
        case .array(let array):
            guard let first = array.first else {
                return ["\(indent)[0 items]"]
            }
            return ["\(indent)[\(array.count) items], first:"] + lines(of: first, depth: depth + 1)
        case .nested(let nested):
            return ["\(indent)(nested)"] + lines(of: nested, depth: depth + 1)
        case .string, .integer, .real, .boolean, .date, .data:
            return []
        }
    }

    static func kind(of value: PropertyListValue) -> String {
        switch value {
        case .dictionary: "dictionary"
        case .array: "array"
        case .string: "string"
        case .integer: "integer"
        case .real: "real"
        case .boolean: "boolean"
        case .date: "date"
        case .data: "data"
        case .nested: "data (property list)"
        }
    }

    private static func dictionaryLines(_ dictionary: [String: PropertyListValue], depth: Int) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        let uuidKeys = dictionary.keys.filter { UUID(uuidString: $0) != nil }.sorted()
        var result: [String] = []
        if let first = uuidKeys.first, let value = dictionary[first] {
            result.append("\(indent)<\(uuidKeys.count) UUID keys>: \(kind(of: value)), first:")
            result += lines(of: value, depth: depth + 1)
        }
        for key in dictionary.keys.sorted() where !uuidKeys.contains(key) {
            guard let value = dictionary[key] else { continue }
            result.append("\(indent)\(key.isEmpty ? "\"\"" : key): \(kind(of: value))")
            result += lines(of: value, depth: depth + 1)
        }
        return result
    }
}
#endif
