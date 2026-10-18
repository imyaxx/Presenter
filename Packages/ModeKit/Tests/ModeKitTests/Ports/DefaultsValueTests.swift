import Foundation
import ModeKit
import Testing

struct DefaultsValueTests {
    @Test(arguments: [DefaultsValue.bool(true), .bool(false), .integer(0), .integer(-7)])
    func roundTripsThroughJSON(value: DefaultsValue) throws {
        #expect(try JSONDecoder().decode(DefaultsValue.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test
    func isEncodedWithTypeDiscriminator() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let json = try #require(
            String(bytes: try encoder.encode([DefaultsValue.bool(false), .integer(1)]), encoding: .utf8))

        #expect(json == #"[{"type":"bool","value":false},{"type":"integer","value":1}]"#)
    }

    @Test(arguments: [#"{"type":"string","value":"x"}"#, #"{"value":true}"#, #"{"type":"bool","value":1}"#])
    func rejectsUnknownTypeMissingDiscriminatorOrWrongValue(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DefaultsValue.self, from: Data(json.utf8))
        }
    }
}
