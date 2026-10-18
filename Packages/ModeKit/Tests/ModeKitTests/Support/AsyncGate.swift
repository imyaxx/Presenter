/// Suspends a fake action inside a call until the test opens the gate, and tells the test when it got there.
actor AsyncGate {
    private var hasArrived = false
    private var isOpen = false
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var passWaiters: [CheckedContinuation<Void, Never>] = []

    /// Called by the fake: records the arrival and suspends until ``open()``.
    func pass() async {
        hasArrived = true
        for continuation in arrivalWaiters {
            continuation.resume()
        }
        arrivalWaiters = []
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { passWaiters.append($0) }
    }

    /// Returns once the fake has reached the gate.
    func waitForArrival() async {
        guard !hasArrived else {
            return
        }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }

    /// Lets every waiting and future caller of ``pass()`` through.
    func open() {
        isOpen = true
        for continuation in passWaiters {
            continuation.resume()
        }
        passWaiters = []
    }
}
