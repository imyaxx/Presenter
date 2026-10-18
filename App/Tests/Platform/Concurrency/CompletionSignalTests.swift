import Testing

@testable import PresenterApp

@Suite(.timeLimit(.minutes(1)))
struct CompletionSignalTests {
    @Test
    func aValueCompletedBeforeTheWaitIsReturnedAtOnce() async {
        let signal = CompletionSignal<Int32>()
        signal.complete(with: 7)

        #expect(await signal.wait() == 7)
    }

    @Test
    func aWaiterReceivesAValueCompletedLater() async {
        let signal = CompletionSignal<Int32>()
        async let received = signal.wait()
        try? await Task.sleep(for: .milliseconds(20))

        signal.complete(with: 3)

        #expect(await received == 3)
    }

    @Test
    func onlyTheFirstValueCounts() async {
        let signal = CompletionSignal<Int32>()
        signal.complete(with: 1)
        signal.complete(with: 2)

        #expect(await signal.wait() == 1)
    }

    @Test
    func aCancelledWaiterReturnsNil() async {
        let signal = CompletionSignal<Int32>()
        let waiter = Task { await signal.wait() }

        waiter.cancel()

        #expect(await waiter.value == nil)
    }

    @Test
    func aBoundedWaitReturnsNilWhenNothingArrives() async {
        let signal = CompletionSignal<Int32>()

        #expect(await signal.wait(upTo: .milliseconds(50)) == nil)
    }
}
