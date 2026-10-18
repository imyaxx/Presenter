import ModeKit
import Testing

struct MenuBarActionTests {
    private static let option = DefaultsKey(domain: "com.apple.controlcenter", name: "AutoHideMenuBarOption")
    private static let hide = DefaultsKey(domain: "NSGlobalDomain", name: "_HIHideMenuBar")
    private static let fullscreen = DefaultsKey(domain: "NSGlobalDomain", name: "AppleMenuBarVisibleInFullscreen")
    private static let keys = [option, hide, fullscreen]
    private static let notification = DistributedNotificationName.menuBarHidingChanged
    private typealias Snapshot = MenuBarAction.Snapshot
    private static let always = MenuBarAction.AppliedState(
        autoHideOption: .integer(0),
        hideMenuBar: .bool(true),
        visibleInFullscreen: .bool(false),
    )

    /// A row of the S1 table (docs/07-macos-integration.md), as stored.
    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        let option: DefaultsValue?
        let hide: DefaultsValue?
        let fullscreen: DefaultsValue?
        var testDescription: String { name }

        var values: [DefaultsKey: DefaultsValue] {
            var values: [DefaultsKey: DefaultsValue] = [:]
            values[MenuBarActionTests.option] = option
            values[MenuBarActionTests.hide] = hide
            values[MenuBarActionTests.fullscreen] = fullscreen
            return values
        }

        var snapshot: MenuBarAction.Snapshot {
            Snapshot(autoHideOption: option, hideMenuBar: hide, visibleInFullscreen: fullscreen)
        }
    }

    static let factory = Row(name: "factory, all absent", option: nil, hide: nil, fullscreen: nil)
    static let never = Row(name: "Never", option: .integer(3), hide: nil, fullscreen: .bool(true))
    static let onDesktopOnly = Row(
        name: "On Desktop Only",
        option: .integer(1),
        hide: .bool(true),
        fullscreen: .bool(true),
    )
    static let inFullScreenOnly = Row(
        name: "In Full Screen Only, explicit",
        option: .integer(2),
        hide: .bool(false),
        fullscreen: .bool(false),
    )
    static let alwaysRow = Row(name: "Always", option: .integer(0), hide: .bool(true), fullscreen: .bool(false))
    static let rowsOtherThanAlways = [factory, never, onDesktopOnly, inFullScreenOnly]

    private let notifier = FakeDistributedNotifier()

    private func makeAction(_ initial: [DefaultsKey: DefaultsValue]) -> (MenuBarAction, FakeDefaultsStore) {
        let defaults = FakeDefaultsStore(initial)
        return (MenuBarAction(defaults: defaults, notifier: notifier), defaults)
    }

    // Per-action scenario: capture reads current state
    @Test(arguments: rowsOtherThanAlways + [alwaysRow])
    func captureReadsTheThreeKeysAndChangesNothing(row: Row) async throws {
        let (action, defaults) = makeAction(row.values)

        #expect(try await action.capture() == row.snapshot)
        #expect(await defaults.calls == Self.keys.map { .read($0) })
        #expect(await notifier.posts.isEmpty)
    }

    // Per-action scenario: apply sets the expected state
    @Test(arguments: rowsOtherThanAlways)
    func applyWritesTheAlwaysRowInKeyOrderAndPostsOnce(row: Row) async throws {
        let (action, defaults) = makeAction(row.values)

        #expect(try await action.apply() == Self.always)
        let writes: [FakeDefaultsStore.Call] = [
            .write(Self.option, .integer(0)), .write(Self.hide, .bool(true)), .write(Self.fullscreen, .bool(false)),
        ]
        #expect(await defaults.calls == Self.keys.map { .read($0) } + writes)
        #expect(await defaults.values == Self.alwaysRow.values)
        #expect(await notifier.posts == [Self.notification])
        #expect(Self.notification.rawValue == "AppleInterfaceMenuBarHidingChangedNotification")
    }

    // Per-action scenario: state already equal to the target
    @Test
    func alreadyAlwaysWritesNothingAndPostsNothingOnApplyOrRestore() async throws {
        let (action, defaults) = makeAction(Self.alwaysRow.values)

        let applied = try await action.apply()
        let outcome = try await action.restore(Self.alwaysRow.snapshot, expecting: applied)

        #expect(outcome == .restored)
        #expect(await defaults.calls == (Self.keys + Self.keys).map { .read($0) })
        #expect(await notifier.posts.isEmpty)
    }

    // Per-action scenario: restore returns to the captured state
    @Test(arguments: rowsOtherThanAlways)
    func restoreReturnsTheThreeKeysToTheSnapshotAndPostsOnce(row: Row) async throws {
        let (action, defaults) = makeAction(Self.alwaysRow.values)

        #expect(try await action.restore(row.snapshot, expecting: Self.always) == .restored)
        #expect(await defaults.values == row.values)
        #expect(await notifier.posts == [Self.notification])
    }

    @Test
    func keysAbsentAtCaptureAreRemovedNeverWritten() async throws {
        let (action, defaults) = makeAction(Self.alwaysRow.values)

        _ = try await action.restore(Self.never.snapshot, expecting: Self.always)

        let changes = await defaults.calls.dropFirst(Self.keys.count)
        #expect(
            Array(changes) == [
                .write(Self.option, .integer(3)), .remove(Self.hide), .write(Self.fullscreen, .bool(true)),
            ])
    }

    // Per-action scenario: restore skips when changed
    @Test
    func restoreIsSkippedWhenTheUserChangedTheSetting() async throws {
        let (action, defaults) = makeAction(Self.inFullScreenOnly.values)

        let outcome = try await action.restore(Self.factory.snapshot, expecting: Self.always)

        #expect(outcome == .skippedBecauseChangedByUser)
        #expect(await defaults.calls == Self.keys.map { .read($0) })
        #expect(await notifier.posts.isEmpty)
    }

    @Test
    func restoreWithoutAppliedStateRestoresAPartlyAppliedSetting() async throws {
        let (action, defaults) = makeAction([Self.option: .integer(0)])

        #expect(try await action.restore(Self.factory.snapshot, expecting: nil) == .restored)
        #expect(await defaults.values.isEmpty)
        #expect(await notifier.posts == [Self.notification])
    }

    @Test
    func restoreWithoutAppliedStateWhenAlreadyAtTheSnapshotDoesNothing() async throws {
        let (action, defaults) = makeAction(Self.never.values)

        #expect(try await action.restore(Self.never.snapshot, expecting: nil) == .restored)
        #expect(await defaults.calls == Self.keys.map { .read($0) })
        #expect(await notifier.posts.isEmpty)
    }

    // Per-action scenario: the system call fails
    @Test
    func aWriteFailingInTheMiddleOfApplyStopsBeforeTheNotification() async {
        let (action, defaults) = makeAction([:])
        await defaults.failNext(.write, for: Self.hide, with: DefaultsError.failed(reason: "read-only"))

        await #expect(throws: DefaultsError.failed(reason: "read-only")) { try await action.apply() }
        #expect(await defaults.values == [Self.option: .integer(0)])
        #expect(await notifier.posts.isEmpty)
    }

    @Test
    func aFailingRestoreStillRestoresTheOtherKeysThenThrowsTheFirstError() async {
        let (action, defaults) = makeAction(Self.alwaysRow.values)
        await defaults.failNext(.write, for: Self.option, with: DefaultsError.failed(reason: "first"))
        await defaults.failNext(.remove, for: Self.hide, with: DefaultsError.failed(reason: "second"))

        await #expect(throws: DefaultsError.failed(reason: "first")) {
            try await action.restore(Self.never.snapshot, expecting: Self.always)
        }
        #expect(
            await defaults.values == [Self.option: .integer(0), Self.hide: .bool(true), Self.fullscreen: .bool(true)])
        #expect(await notifier.posts == [Self.notification])
    }

    @Test
    func aKeyThatCannotBeReadFailsCaptureAndRestore() async {
        let (action, defaults) = makeAction([:])
        let error = DefaultsError.unsupportedValueType(Self.hide)
        await defaults.failNext(.read, for: Self.hide, with: error)
        await #expect(throws: error) { try await action.capture() }

        await defaults.failNext(.read, for: Self.hide, with: error)
        await #expect(throws: error) { try await action.restore(Self.factory.snapshot, expecting: nil) }
        #expect(await notifier.posts.isEmpty)
    }
}
