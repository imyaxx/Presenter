import Foundation

/// Compares wallpaper stores without ModeKit knowing their format (ADR-039).
///
/// The wallpaper store (`Index.plist`, ADR-027) is undocumented; its structure is inspected and validated against the
/// real system in the adapter, not in ModeKit. Threading: implementations are `Sendable`; a pure computation.
public protocol WallpaperStoreInspector: Sendable {
    /// Equal fingerprints if and only if the wallpaper configuration of every display and Space this app can change is
    /// equal. Volatile fields (timestamps such as `LastUse`) must not influence it.
    ///
    /// - Throws: ``WallpaperStoreError/unrecognizedFormat(reason:)`` when the data is not a wallpaper store the
    ///   inspector understands.
    func fingerprint(of store: Data) throws -> WallpaperStoreFingerprint
}
