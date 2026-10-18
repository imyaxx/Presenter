import CoreFoundation
import Foundation
import ModeKit
import Testing

@testable import PresenterApp

/// Uses only a throwaway domain `dev.imyaxx.presenter.tests.<UUID>`, one per run of this suite, with a fresh key per
/// test; the keys and the plist file are removed after the suite (ADR-040). Never touches a real application's domain.
@Suite(.timeLimit(.minutes(1)), .deletes(.defaultsStoreSuite))
struct CFPreferencesDefaultsStoreTests {
    private static let domain = ThrowawayPreferencesDomain.defaultsStoreSuite

    enum UnsupportedValue: CaseIterable, Sendable {
        case string, floatingPoint

        var propertyList: CFPropertyList {
            switch self {
            case .string: "text" as CFString
            case .floatingPoint: 1.5 as CFNumber
            }
        }
    }

    private let store = CFPreferencesDefaultsStore()

    @Test
    func anAbsentKeyReadsAsNil() async throws {
        #expect(try await store.value(for: Self.domain.key("absent")) == nil)
    }

    @Test(arguments: [DefaultsValue.bool(true), .bool(false), .integer(0), .integer(1), .integer(3), .integer(-2)])
    func aValueRoundTripsWithItsType(value: DefaultsValue) async throws {
        let key = Self.domain.key("value")

        try await store.set(value, for: key)

        #expect(try await store.value(for: key) == value)
    }

    @Test(arguments: UnsupportedValue.allCases)
    func aValueOfAnotherTypeIsUnsupported(stored: UnsupportedValue) async throws {
        let key = Self.domain.key("other")
        Self.domain.writeDirectly(stored.propertyList, for: key)

        await #expect(throws: DefaultsError.unsupportedValueType(key)) { try await store.value(for: key) }
    }

    @Test
    func removingAnAbsentKeySucceedsAndRemovingAPresentKeyDeletesIt() async throws {
        let key = Self.domain.key("removed")
        try await store.remove(key)
        try await store.set(.integer(4), for: key)

        try await store.remove(key)

        #expect(try await store.value(for: key) == nil)
    }

    @Test
    func aWriteByAnotherProcessIsSeenByTheNextRead() async throws {
        let key = Self.domain.key("external")
        #expect(try await store.value(for: key) == nil)
        let write = ProcessCommand(
            executableURL: URL(filePath: "/usr/bin/defaults"),
            arguments: ["write", Self.domain.name, key.name, "-int", "7"],
            timeout: .seconds(10),
        )

        #expect(try await FoundationProcessRunner().run(write).exitCode == 0)

        #expect(try await store.value(for: key) == .integer(7))
    }

    @Test
    func theGlobalDomainNameMapsToAnyApplication() {
        let global = CFPreferencesDefaultsStore.applicationID(for: "NSGlobalDomain") as String
        let finder = CFPreferencesDefaultsStore.applicationID(for: "com.apple.finder") as String

        #expect(global == kCFPreferencesAnyApplication as String)
        #expect(finder == "com.apple.finder")
    }

    @Test
    func booleansAreMappedByTypeNotByNumberBridging() throws {
        let key = DefaultsKey(domain: "unused", name: "unused")

        #expect(try CFPreferencesDefaultsStore.defaultsValue(from: kCFBooleanTrue, for: key) == .bool(true))
        #expect(try CFPreferencesDefaultsStore.defaultsValue(from: 1 as CFNumber, for: key) == .integer(1))
        #expect(try CFPreferencesDefaultsStore.defaultsValue(from: 0 as CFNumber, for: key) == .integer(0))
    }
}
