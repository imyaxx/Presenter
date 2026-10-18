/// A preference value an action reads or writes. Only the types the actions use are modeled.
///
/// JSON: `{ "type": "bool", "value": true }` or `{ "type": "integer", "value": 1 }`. Unknown types fail decoding.
public enum DefaultsValue: Hashable, Sendable, Codable {
    case bool(Bool)
    case integer(Int)

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    private enum Kind: String, Codable {
        case bool, integer
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case .integer:
            self = .integer(try container.decode(Int.self, forKey: .value))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bool(let value):
            try container.encode(Kind.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        case .integer(let value):
            try container.encode(Kind.integer, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}
