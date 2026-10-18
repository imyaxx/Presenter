import Foundation

/// A type-erased ``ActionRestorer`` that restores from an ``ActionRecord``'s encoded data.
struct AnyActionRestorer: Sendable {
    let identifier: ActionIdentifier
    private let restoreRecord: @Sendable (_ snapshotData: Data, _ appliedData: Data?) async throws -> RestoreOutcome

    init<Restorer: ActionRestorer>(_ restorer: Restorer) {
        let identifier = restorer.identifier
        self.identifier = identifier
        restoreRecord = { snapshotData, appliedData in
            let snapshot = try Self.decode(Restorer.Snapshot.self, from: snapshotData, for: identifier)
            let applied = try appliedData.map {
                try Self.decode(Restorer.AppliedState.self, from: $0, for: identifier)
            }
            return try await restorer.restore(snapshot, expecting: applied)
        }
    }

    /// Decodes the record's data and restores. A nil `appliedData` restores unconditionally.
    ///
    /// - Throws: ``ActionError/undecodableRecord(_:reason:)`` or the restorer's own error.
    func restore(_ record: ActionRecord) async throws -> RestoreOutcome {
        try await restoreRecord(record.snapshotData, record.appliedData)
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data,
        for identifier: ActionIdentifier,
    ) throws(ActionError) -> Value {
        do {
            return try PersistenceCoding.makeDecoder().decode(type, from: data)
        } catch {
            throw .undecodableRecord(identifier, reason: String(describing: error))
        }
    }
}
