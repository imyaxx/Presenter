import ModeKit

/// An in-memory ``DefaultsStore`` with an ordered call log and per-operation (optionally per-key) failure injection.
actor FakeDefaultsStore: DefaultsStore {
    enum Call: Equatable, Sendable {
        case read(DefaultsKey)
        case write(DefaultsKey, DefaultsValue)
        case remove(DefaultsKey)
    }

    enum Operation: Hashable, Sendable {
        case read, write, remove
    }

    /// The whole stored state, for comparing before and after a session.
    private(set) var values: [DefaultsKey: DefaultsValue]
    private(set) var calls: [Call] = []
    private var failures: [Operation: (key: DefaultsKey?, error: any Error)] = [:]

    init(_ values: [DefaultsKey: DefaultsValue] = [:]) {
        self.values = values
    }

    /// Makes the next call of `operation` throw `error`; with `key`, the next call of `operation` on that key.
    func failNext(_ operation: Operation, for key: DefaultsKey? = nil, with error: any Error) {
        failures[operation] = (key, error)
    }

    /// Changes a value the way another process would (the user, or System Events), without logging a call.
    func place(_ value: DefaultsValue?, for key: DefaultsKey) {
        values[key] = value
    }

    func value(for key: DefaultsKey) async throws -> DefaultsValue? {
        calls.append(.read(key))
        try throwIfScripted(.read, key)
        return values[key]
    }

    func set(_ value: DefaultsValue, for key: DefaultsKey) async throws {
        calls.append(.write(key, value))
        try throwIfScripted(.write, key)
        values[key] = value
    }

    func remove(_ key: DefaultsKey) async throws {
        calls.append(.remove(key))
        try throwIfScripted(.remove, key)
        values[key] = nil
    }

    private func throwIfScripted(_ operation: Operation, _ key: DefaultsKey) throws {
        guard let failure = failures[operation], failure.key == nil || failure.key == key else {
            return
        }
        failures[operation] = nil
        throw failure.error
    }
}
