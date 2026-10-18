import ModeKit

/// An in-memory ``DefaultsStore`` with an ordered call log and per-operation failure injection.
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
    private var failures: [Operation: any Error] = [:]

    init(_ values: [DefaultsKey: DefaultsValue] = [:]) {
        self.values = values
    }

    /// Makes the next call of `operation` throw `error`.
    func failNext(_ operation: Operation, with error: any Error) {
        failures[operation] = error
    }

    /// Changes a value the way another process would (the user, or System Events), without logging a call.
    func place(_ value: DefaultsValue?, for key: DefaultsKey) {
        values[key] = value
    }

    func value(for key: DefaultsKey) async throws -> DefaultsValue? {
        calls.append(.read(key))
        try throwIfScripted(.read)
        return values[key]
    }

    func set(_ value: DefaultsValue, for key: DefaultsKey) async throws {
        calls.append(.write(key, value))
        try throwIfScripted(.write)
        values[key] = value
    }

    func remove(_ key: DefaultsKey) async throws {
        calls.append(.remove(key))
        try throwIfScripted(.remove)
        values[key] = nil
    }

    private func throwIfScripted(_ operation: Operation) throws {
        if let error = failures.removeValue(forKey: operation) {
            throw error
        }
    }
}
