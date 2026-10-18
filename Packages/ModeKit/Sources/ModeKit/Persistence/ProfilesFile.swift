import Foundation

/// The top level of `profiles.json`: `{ "schemaVersion": 1, "profiles": [...] }`.
struct ProfilesFile: VersionedFileEnvelope {
    static var fileName: String { "profiles.json" }

    let schemaVersion: Int
    let profiles: [Profile]

    func validated() throws(StoreError) -> ProfilesFile {
        do {
            return ProfilesFile(schemaVersion: schemaVersion, profiles: try Self.validate(profiles))
        } catch {
            throw .corrupted(fileName: Self.fileName, reason: "invalid profile: \(error)")
        }
    }

    /// Validates every profile, trims names, and checks that identifiers are unique.
    ///
    /// - Throws: ``StoreError/invalidProfile(_:)`` or ``StoreError/duplicateProfileID(_:)``.
    static func validate(_ profiles: [Profile]) throws(StoreError) -> [Profile] {
        var identifiers: Set<UUID> = []
        var validatedProfiles: [Profile] = []
        for profile in profiles {
            do {
                validatedProfiles.append(try ProfileValidation.validate(profile))
            } catch {
                throw .invalidProfile(error)
            }
            let (isNew, _) = identifiers.insert(profile.id)
            guard isNew else {
                throw .duplicateProfileID(profile.id)
            }
        }
        return validatedProfiles
    }
}
