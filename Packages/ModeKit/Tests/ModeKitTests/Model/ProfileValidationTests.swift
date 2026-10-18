import Foundation
import ModeKit
import Testing

struct ProfileValidationTests {
    @Test
    func validProfileIsReturnedWithTrimmedName() throws {
        let profile = ProfileBuilder(name: "  \tScreen share\n ").build()

        let validated = try ProfileValidation.validate(profile)

        #expect(validated.name == "Screen share")
        #expect(validated.steps == profile.steps)
        #expect(validated.id == profile.id)
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func emptyNameIsRejected(name: String) {
        #expect(throws: ProfileValidationError.emptyName) {
            try ProfileValidation.validate(ProfileBuilder(name: name).build())
        }
    }

    @Test
    func sixtyCharacterNameIsAccepted() throws {
        let name = String(repeating: "x", count: 60)

        #expect(try ProfileValidation.validate(ProfileBuilder(name: name).build()).name == name)
    }

    @Test
    func sixtyOneCharacterNameIsRejected() {
        #expect(throws: ProfileValidationError.nameTooLong(characterCount: 61)) {
            try ProfileValidation.validate(ProfileBuilder(name: String(repeating: "x", count: 61)).build())
        }
    }

    @Test
    func nameLengthCountsCharactersNotBytes() throws {
        let name = String(repeating: "Запись🎥", count: 8) + "Ок🧑‍💻"

        let validated = try ProfileValidation.validate(ProfileBuilder(name: name).build())

        #expect(validated.name.utf8.count > ProfileValidation.nameLengthRange.upperBound)
        #expect(validated.name.count == 59)
    }

    @Test(arguments: [
        [ProfileStep.hideDock, .hideDesktopIcons, .hideDock],
        [.hideApps(exclusions: []), .hideApps(exclusions: [])],
    ])
    func duplicateStepKindIsRejected(steps: [ProfileStep]) {
        #expect(throws: ProfileValidationError.duplicateStep(steps[steps.count - 1].actionIdentifier)) {
            try ProfileValidation.validate(ProfileBuilder(steps: steps).build())
        }
    }

    @Test
    func twoWallpaperStepsAreDuplicates() {
        let color = WallpaperChoice.solidColor(SolidColor(red: 0, green: 0, blue: 0))
        let steps = [ProfileStep.wallpaper(color, displays: .allDisplays), .wallpaper(color, displays: .allDisplays)]

        #expect(throws: ProfileValidationError.duplicateStep(.wallpaper)) {
            try ProfileValidation.validate(ProfileBuilder(steps: steps).build())
        }
    }

    @Test
    func emptySpecificDisplaySelectionIsRejected() {
        let step = ProfileStep.wallpaper(.solidColor(SolidColor(red: 1, green: 2, blue: 3)), displays: .specific([]))

        #expect(throws: ProfileValidationError.emptyDisplaySelection) {
            try ProfileValidation.validate(ProfileBuilder(steps: [step]).build())
        }
    }

    @Test
    func imageThatIsNotAFileURLIsRejected() throws {
        let remote = try #require(URL(string: "https://example.com/wallpaper.png"))
        let step = ProfileStep.wallpaper(.image(remote), displays: .allDisplays)

        #expect(throws: ProfileValidationError.imageNotFileURL) {
            try ProfileValidation.validate(ProfileBuilder(steps: [step]).build())
        }
    }

    @Test
    func emptyStepListIsValid() throws {
        #expect(try ProfileValidation.validate(ProfileBuilder(steps: []).build()).steps.isEmpty)
    }
}
