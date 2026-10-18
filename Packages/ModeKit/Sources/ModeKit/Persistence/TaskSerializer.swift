/// Runs async operations one after another, in call order.
///
/// An actor alone does not serialize a read-modify-write sequence: it re-enters at every `await`. Each store runs
/// its file operations through one `TaskSerializer`, so two concurrent saves never interleave. An operation keeps
/// running when its caller is cancelled, so a started write always finishes.
actor TaskSerializer {
    private var tail = Task<Void, Never> {}

    func run<Value: Sendable>(_ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let previous = tail
        let current = Task {
            await previous.value
            return try await operation()
        }
        tail = Task { _ = await current.result }
        return try await current.value
    }
}
