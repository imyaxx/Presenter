/// The top level of `session.json`: `{ "schemaVersion": 1, "session": {...} }`.
struct SessionFile: VersionedFileEnvelope {
    static var fileName: String { "session.json" }

    let schemaVersion: Int
    let session: SessionRecord

    func validated() throws(StoreError) -> SessionFile {
        self
    }
}
