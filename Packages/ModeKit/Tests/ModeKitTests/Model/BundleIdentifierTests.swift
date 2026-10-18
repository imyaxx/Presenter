import Foundation
import ModeKit
import Testing

struct BundleIdentifierTests {
    @Test(arguments: [
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.microsoft.VSCode",
        "a.b",
        "com.example.my-app",
        "com.example.app2",
        "1password.app",
        String(repeating: "a", count: 127) + "." + String(repeating: "b", count: 127),
    ])
    func acceptsStrictReverseDNSIdentifier(value: String) throws {
        #expect(try BundleIdentifier(value).rawValue == value)
    }

    @Test(arguments: [
        "",
        "safari",
        ".com.apple",
        "com.apple.",
        "com..apple",
        "com.-apple",
        "com.apple-",
        "com.app_le",
        "com.apple.Safari\"; do shell script \"rm",
        "com.apple Safari",
        "com.яблоко.app",
        "com.apple.😀",
        String(repeating: "a", count: 128) + "." + String(repeating: "b", count: 127),
    ])
    func rejectsAnythingElse(value: String) {
        #expect(throws: ProfileValidationError.invalidBundleIdentifier(value)) {
            try BundleIdentifier(value)
        }
    }

    @Test
    func decodingInvalidValueFails() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([BundleIdentifier].self, from: Data(#"["com.apple..Safari"]"#.utf8))
        }
    }

    @Test
    func encodesAsPlainString() throws {
        let data = try JSONEncoder().encode([try BundleIdentifier("com.apple.Safari")])

        #expect(try #require(String(bytes: data, encoding: .utf8)) == #"["com.apple.Safari"]"#)
    }
}
