import Foundation
import Testing

@testable import PresenterApp

struct PropertyListValueTests {
    @Test
    func nestedBinaryPropertyListsAreDecodedAndOtherDataStaysOpaque() throws {
        let configuration: [String: Any] = ["type": "imageFile"]
        let nested = try PropertyListSerialization.data(fromPropertyList: configuration, format: .binary, options: 0)
        let undecodable = Data("bplist00".utf8) + Data([0xFF, 0xFE])
        let plain = Data([0x01, 0x02])
        let store = try PropertyListSerialization.data(
            fromPropertyList: ["nested": nested, "undecodable": undecodable, "plain": plain],
            format: .binary,
            options: 0,
        )

        let value = try PropertyListValue.decode(store)

        #expect(
            value
                == .dictionary([
                    "nested": .nested(.dictionary(["type": .string("imageFile")])),
                    "undecodable": .data(undecodable),
                    "plain": .data(plain),
                ]))
    }

    @Test
    func booleansIntegersAndRealsStayDistinct() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["flag": true, "count": 1, "share": 0.5],
            format: .xml,
            options: 0,
        )

        #expect(
            try PropertyListValue.decode(data)
                == .dictionary(["flag": .boolean(true), "count": .integer(1), "share": .real(0.5)]))
    }

    @Test
    func theCanonicalTextIgnoresExcludedKeysAtAnyDepth() {
        let value = PropertyListValue.dictionary([
            "b": .array([.dictionary(["LastUse": .date(Date()), "x": .integer(1)])]),
            "a": .string("text"),
        ])

        #expect(value.canonicalText(excluding: ["LastUse"]) == "{1:a=s4:text;1:b=[{1:x=i1}]}")
    }
}
