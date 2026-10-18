/// The top level of a persisted JSON file: a `schemaVersion` header plus the content.
protocol VersionedFileEnvelope: Codable, Sendable {
    /// The file name inside the store's directory.
    static var fileName: String { get }
    /// The schema version the file was written with.
    var schemaVersion: Int { get }
    /// Returns the envelope with its content validated and normalized.
    ///
    /// - Throws: ``StoreError/corrupted(fileName:reason:)`` when decoded content breaks a rule.
    func validated() throws(StoreError) -> Self
}
