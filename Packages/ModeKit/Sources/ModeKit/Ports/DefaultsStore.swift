/// Reads, writes and removes single preference values of other applications' domains.
///
/// Local preference access has no timeout by design, like ``FileStore``: it is not an external wait.
/// Threading: implementations are `Sendable`; methods may be called from any context.
public protocol DefaultsStore: Sendable {
    /// Returns the value, or nil when the key is absent. Absent is not the same as `false`.
    ///
    /// - Throws: ``DefaultsError/unsupportedValueType(_:)`` for a type other than ``DefaultsValue``'s, or
    ///   ``DefaultsError/failed(reason:)``.
    func value(for key: DefaultsKey) async throws -> DefaultsValue?

    /// Writes the value with its type.
    ///
    /// - Throws: ``DefaultsError/failed(reason:)``.
    func set(_ value: DefaultsValue, for key: DefaultsKey) async throws

    /// Removes the key. Removing an absent key succeeds.
    ///
    /// - Throws: ``DefaultsError/failed(reason:)``.
    func remove(_ key: DefaultsKey) async throws
}
