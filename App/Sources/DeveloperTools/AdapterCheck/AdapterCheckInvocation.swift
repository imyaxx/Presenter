#if DEBUG
import Foundation
import ModeKit

/// One launch of the adapter check tool, parsed from the command line (`--adapter-check <command> ...`, ADR-042).
struct AdapterCheckInvocation: Equatable, Sendable {
    /// Options shared by `run` and `activate`.
    struct SessionOptions: Equatable, Sendable {
        /// A profile name in the check directory's `profiles.json`; nil with `hideOnly` builds a hide-only profile.
        let profileName: String?
        /// The only applications a `hideApps` step may hide; every other running application is excluded.
        let hideOnly: [BundleIdentifier]?
        /// Seconds between activation and deactivation (`run`), or before exiting without deactivating (`activate`).
        let holdSeconds: Int
    }

    enum Command: Equatable, Sendable {
        case world
        case storeStructure
        case run(SessionOptions)
        case activate(SessionOptions)
        case recover
        case wallpaperLatency(runs: Int)
        case wallpaperInterrupt
        case notifyMenuBar

        var name: String {
            switch self {
            case .world: "world"
            case .storeStructure: "store-structure"
            case .run: "run"
            case .activate: "activate"
            case .recover: "recover"
            case .wallpaperLatency: "wallpaper-latency"
            case .wallpaperInterrupt: "wallpaper-interrupt"
            case .notifyMenuBar: "notify-menubar"
            }
        }

        /// Commands that change the real system need a fresh backup (`--backup`).
        var changesTheSystem: Bool {
            switch self {
            case .world, .storeStructure: false
            case .run, .activate, .recover, .wallpaperLatency, .wallpaperInterrupt, .notifyMenuBar: true
            }
        }
    }

    static let flag = "--adapter-check"

    let command: Command
    let resultURL: URL
    let checkDirectory: URL
    let backupDirectory: URL?

    /// Returns nil when `arguments` do not contain ``flag``: a normal launch.
    ///
    /// Arguments that start with a single dash (for example `-AppleLanguages "(ru)"`) belong to the system and are
    /// skipped with their value.
    /// - Throws: ``AdapterCheckArgumentError``.
    static func parse(
        _ arguments: [String],
        defaultCheckDirectory: URL,
    ) throws(AdapterCheckArgumentError) -> AdapterCheckInvocation? {
        guard let flagIndex = arguments.firstIndex(of: flag) else {
            return nil
        }
        var options = try AdapterCheckOptions(arguments[arguments.index(after: flagIndex)...])
        guard let commandName = options.commandName else {
            throw AdapterCheckArgumentError.missingCommand
        }
        let command = try makeCommand(commandName, options: &options)
        guard let resultPath = try options.take("--result") else {
            throw AdapterCheckArgumentError.missingValue("--result")
        }
        let checkDirectory = try options.take("--check-dir").map { URL(filePath: $0, directoryHint: .isDirectory) }
        let backupDirectory = try options.take("--backup").map { URL(filePath: $0, directoryHint: .isDirectory) }
        try options.requireNothingLeft()
        return AdapterCheckInvocation(
            command: command,
            resultURL: URL(filePath: resultPath),
            checkDirectory: checkDirectory ?? defaultCheckDirectory,
            backupDirectory: backupDirectory,
        )
    }

    private static func makeCommand(
        _ name: String,
        options: inout AdapterCheckOptions,
    ) throws(AdapterCheckArgumentError) -> Command {
        switch name {
        case "world": return .world
        case "store-structure": return .storeStructure
        case "run": return .run(try sessionOptions(&options, defaultHoldSeconds: 8))
        case "activate": return .activate(try sessionOptions(&options, defaultHoldSeconds: 0))
        case "recover": return .recover
        case "wallpaper-latency": return .wallpaperLatency(runs: try options.takeCount("--runs") ?? 12)
        case "wallpaper-interrupt": return .wallpaperInterrupt
        case "notify-menubar": return .notifyMenuBar
        default: throw AdapterCheckArgumentError.unknownCommand(name)
        }
    }

    private static func sessionOptions(
        _ options: inout AdapterCheckOptions,
        defaultHoldSeconds: Int,
    ) throws(AdapterCheckArgumentError) -> SessionOptions {
        let profileName = try options.take("--profile")
        let hideOnly = try options.take("--hide-only").map { list throws(AdapterCheckArgumentError) in
            try bundleIdentifiers(list)
        }
        guard profileName != nil || hideOnly != nil else {
            throw AdapterCheckArgumentError.missingValue("--profile or --hide-only")
        }
        let hold = try options.takeCount("--hold-seconds", minimum: 0) ?? defaultHoldSeconds
        return SessionOptions(profileName: profileName, hideOnly: hideOnly, holdSeconds: hold)
    }

    private static func bundleIdentifiers(_ list: String) throws(AdapterCheckArgumentError) -> [BundleIdentifier] {
        var identifiers: [BundleIdentifier] = []
        for rawValue in list.split(separator: ",").map(String.init) {
            do {
                identifiers.append(try BundleIdentifier(rawValue))
            } catch {
                throw AdapterCheckArgumentError.invalidValue(option: "--hide-only", value: rawValue)
            }
        }
        guard !identifiers.isEmpty else {
            throw AdapterCheckArgumentError.invalidValue(option: "--hide-only", value: list)
        }
        return identifiers
    }
}
#endif
