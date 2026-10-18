import CoreFoundation
import Foundation

/// A decoded property-list value with nested binary property lists decoded too, and a canonical text form that does
/// not depend on key order or on the encoding (binary or XML).
indirect enum PropertyListValue: Equatable, Sendable {
    case dictionary([String: PropertyListValue])
    case array([PropertyListValue])
    case string(String)
    case integer(Int)
    case real(Double)
    case boolean(Bool)
    case date(Date)
    case data(Data)
    /// `Data` that held a binary property list, decoded.
    case nested(PropertyListValue)

    private static let binaryPropertyListMagic = Data("bplist".utf8)

    /// Decodes property-list bytes.
    ///
    /// - Throws: An error of `PropertyListSerialization` when the bytes are not a property list.
    static func decode(_ bytes: Data) throws -> PropertyListValue {
        try PropertyListValue(object: PropertyListSerialization.propertyList(from: bytes, format: nil))
    }

    /// Converts the Foundation object graph `PropertyListSerialization` returns. This is the only place where untyped
    /// values are inspected; booleans are told apart from numbers by Core Foundation type identifier.
    private init(object: Any) throws {
        switch object {
        case let dictionary as [String: Any]:
            self = .dictionary(try dictionary.mapValues(PropertyListValue.init(object:)))
        case let array as [Any]:
            self = .array(try array.map(PropertyListValue.init(object:)))
        case let string as String:
            self = .string(string)
        case let date as Date:
            self = .date(date)
        case let data as Data:
            self = Self.decodeNested(data)
        case let number as NSNumber:
            self = Self.number(number)
        default:
            throw CocoaError(.propertyListReadCorrupt)
        }
    }

    private static func number(_ number: NSNumber) -> PropertyListValue {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .boolean(number.boolValue)
        }
        return CFNumberIsFloatType(number as CFNumber) ? .real(number.doubleValue) : .integer(number.intValue)
    }

    /// Bytes that start like a binary property list but do not decode stay opaque data.
    private static func decodeNested(_ data: Data) -> PropertyListValue {
        guard data.starts(with: binaryPropertyListMagic) else {
            return .data(data)
        }
        // Not decodable as a property list means it is opaque data, which is a valid outcome here.
        guard let nested = try? decode(data) else {
            return .data(data)
        }
        return .nested(nested)
    }

    /// A text form with sorted keys and length-prefixed strings, leaving out every dictionary entry whose key is in
    /// `excludedKeys`, at any depth. Equal values give equal text.
    func canonicalText(excluding excludedKeys: Set<String>) -> String {
        switch self {
        case .dictionary(let dictionary):
            let entries = dictionary.keys.sorted().filter { !excludedKeys.contains($0) }.map { key in
                Self.lengthPrefixed(key) + "=" + (dictionary[key]?.canonicalText(excluding: excludedKeys) ?? "")
            }
            return "{" + entries.joined(separator: ";") + "}"
        case .array(let array):
            return "[" + array.map { $0.canonicalText(excluding: excludedKeys) }.joined(separator: ",") + "]"
        case .string(let string): return "s" + Self.lengthPrefixed(string)
        case .integer(let integer): return "i\(integer)"
        case .real(let real): return "r\(real.bitPattern)"
        case .boolean(let boolean): return boolean ? "b1" : "b0"
        case .date(let date): return "d\(date.timeIntervalSinceReferenceDate.bitPattern)"
        case .data(let data): return "x" + data.base64EncodedString()
        case .nested(let nested): return "p(" + nested.canonicalText(excluding: excludedKeys) + ")"
        }
    }

    private static func lengthPrefixed(_ string: String) -> String {
        "\(string.utf8.count):\(string)"
    }
}
