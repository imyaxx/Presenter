import Foundation
import ModeKit
import Testing

struct AutoExitTests {
    @Test(arguments: [60, 1_800, 86_400])
    func acceptsWholeSecondsWithinOneMinuteToOneDay(seconds: Int) throws {
        let autoExit = try AutoExit(seconds: seconds)

        #expect(autoExit.seconds == seconds)
        #expect(autoExit.duration == .seconds(seconds))
    }

    @Test(arguments: [Int.min, -1, 0, 59, 86_401])
    func rejectsSecondsOutsideRange(seconds: Int) {
        #expect(throws: ProfileValidationError.autoExitOutOfRange(seconds: seconds)) {
            try AutoExit(seconds: seconds)
        }
    }

    @Test
    func decodingOutOfRangeValueFails() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([AutoExit].self, from: Data("[30]".utf8))
        }
    }

    @Test
    func profileOmitsAutoExitSecondsWhenNil() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let json = try #require(String(bytes: try encoder.encode(ProfileBuilder(steps: []).build()), encoding: .utf8))

        #expect(!json.contains("autoExitSeconds"))
    }

    @Test
    func profileWritesAutoExitAsSeconds() throws {
        let profile = ProfileBuilder(steps: [], autoExit: try AutoExit(seconds: 1_800)).build()

        let json = try #require(String(bytes: try JSONEncoder().encode(profile), encoding: .utf8))

        #expect(json.contains(#""autoExitSeconds":1800"#))
        #expect(try JSONDecoder().decode(Profile.self, from: Data(json.utf8)) == profile)
    }
}
