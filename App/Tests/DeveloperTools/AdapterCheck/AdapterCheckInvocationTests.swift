#if DEBUG
import Foundation
import ModeKit
import Testing

@testable import PresenterApp

struct AdapterCheckInvocationTests {
    private static let home = URL(filePath: "/Check/Home/presenter-check", directoryHint: .isDirectory)

    private func parse(_ arguments: [String]) throws -> AdapterCheckInvocation? {
        try AdapterCheckInvocation.parse(["/path/Presenter"] + arguments, defaultCheckDirectory: Self.home)
    }

    private func parseCommand(_ arguments: [String]) throws -> AdapterCheckInvocation.Command? {
        try parse(["--adapter-check"] + arguments + ["--result", "/tmp/r.json"])?.command
    }

    @Test
    func aNormalLaunchIsNotACheck() throws {
        #expect(try parse([]) == nil)
        #expect(try parse(["-AppleLanguages", "(ru)"]) == nil)
    }

    @Test
    func worldNeedsOnlyAResultFile() throws {
        let invocation = try #require(try parse(["--adapter-check", "world", "--result", "/tmp/r.json"]))

        #expect(invocation.command == .world)
        #expect(invocation.resultURL.path(percentEncoded: false) == "/tmp/r.json")
        #expect(invocation.checkDirectory == Self.home)
        #expect(invocation.backupDirectory == nil)
        #expect(!invocation.command.changesTheSystem)
    }

    @Test
    func runTakesAProfileAndHoldsEightSecondsByDefault() throws {
        let command = try parseCommand(["run", "--profile", "dock", "--backup", "/b"])

        #expect(command == .run(.init(profileName: "dock", hideOnly: nil, holdSeconds: 8)))
        #expect(command?.changesTheSystem == true)
    }

    @Test
    func activateHoldsNothingByDefaultAndAcceptsAHold() throws {
        #expect(
            try parseCommand(["activate", "--profile", "all-five"])
                == .activate(.init(profileName: "all-five", hideOnly: nil, holdSeconds: 0)))
        #expect(
            try parseCommand(["activate", "--profile", "x", "--hold-seconds", "60"])
                == .activate(.init(profileName: "x", hideOnly: nil, holdSeconds: 60)))
    }

    @Test
    func hideOnlyIsACommaSeparatedListOfBundleIdentifiers() throws {
        let expected = [try BundleIdentifier("com.apple.TextEdit"), try BundleIdentifier("com.apple.calculator")]

        #expect(
            try parseCommand(["run", "--hide-only", "com.apple.TextEdit,com.apple.calculator"])
                == .run(.init(profileName: nil, hideOnly: expected, holdSeconds: 8)))
    }

    @Test
    func theOtherCommandsAndTheirDefaults() throws {
        #expect(try parseCommand(["store-structure"]) == .storeStructure)
        #expect(try parseCommand(["recover"]) == .recover)
        #expect(try parseCommand(["wallpaper-latency"]) == .wallpaperLatency(runs: 12))
        #expect(try parseCommand(["wallpaper-latency", "--runs", "3"]) == .wallpaperLatency(runs: 3))
        #expect(try parseCommand(["wallpaper-interrupt"]) == .wallpaperInterrupt)
        #expect(try parseCommand(["notify-menubar"]) == .notifyMenuBar)
    }

    @Test
    func systemArgumentsAreSkippedWithTheirValue() throws {
        let invocation = try parse([
            "--adapter-check", "world", "-AppleLanguages", "(ru)", "--result", "/r", "--check-dir", "/c",
        ])

        #expect(invocation?.command == .world)
        #expect(invocation?.checkDirectory.path(percentEncoded: false) == "/c/")
    }

    enum BadCommandLine: CaseIterable, Sendable {
        case noCommand, unknownCommand, noResult, unknownOption, duplicateOption, valueMissing, extraArgument
        case runWithoutProfile, invalidBundleIdentifier, zeroRuns, negativeHold

        var arguments: [String] {
            switch self {
            case .noCommand: ["--adapter-check", "--result", "/r"]
            case .unknownCommand: ["--adapter-check", "reset", "--result", "/r"]
            case .noResult: ["--adapter-check", "world"]
            case .unknownOption: ["--adapter-check", "world", "--profile", "x", "--result", "/r"]
            case .duplicateOption: ["--adapter-check", "world", "--result", "/r", "--result", "/s"]
            case .valueMissing: ["--adapter-check", "world", "--result"]
            case .extraArgument: ["--adapter-check", "world", "again", "--result", "/r"]
            case .runWithoutProfile: ["--adapter-check", "run", "--result", "/r"]
            case .invalidBundleIdentifier: ["--adapter-check", "run", "--hide-only", "not valid", "--result", "/r"]
            case .zeroRuns: ["--adapter-check", "wallpaper-latency", "--runs", "0", "--result", "/r"]
            case .negativeHold: ["--adapter-check", "run", "--profile", "x", "--hold-seconds", "-1", "--result", "/r"]
            }
        }

        var error: AdapterCheckArgumentError {
            switch self {
            case .noCommand: .missingCommand
            case .unknownCommand: .unknownCommand("reset")
            case .noResult: .missingValue("--result")
            case .unknownOption: .unknownOption("--profile")
            case .duplicateOption: .duplicateOption("--result")
            case .valueMissing: .missingValue("--result")
            case .extraArgument: .unexpectedArgument("again")
            case .runWithoutProfile: .missingValue("--profile or --hide-only")
            case .invalidBundleIdentifier: .invalidValue(option: "--hide-only", value: "not valid")
            case .zeroRuns: .invalidValue(option: "--runs", value: "0")
            case .negativeHold: .invalidValue(option: "--hold-seconds", value: "-1")
            }
        }
    }

    @Test(arguments: BadCommandLine.allCases)
    func aBadCommandLineIsRejected(bad: BadCommandLine) {
        #expect(throws: bad.error) {
            try AdapterCheckInvocation.parse(bad.arguments, defaultCheckDirectory: Self.home)
        }
    }
}
#endif
