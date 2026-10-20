import Testing

@testable import PresenterApp

struct NSRunningApplicationInstanceGuardTests {
    @Test(arguments: [
        ([Int32](), Int32?.none),
        ([42], .none),
        ([42, 77], .some(77)),
        ([77, 42], .some(77)),
    ])
    func anotherInstanceIsAnyProcessButTheCurrentOne(running: [Int32], expected: Int32?) {
        #expect(NSRunningApplicationInstanceGuard.otherInstance(among: running, current: 42) == expected)
    }
}
