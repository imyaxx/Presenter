import Foundation

/// The single home of every profile rule.
///
/// ``BundleIdentifier`` and ``AutoExit`` enforce their rules on construction by calling into this type, so an
/// invalid value of either type cannot exist. ``validate(_:)`` checks the rules that span a whole profile.
///
/// Thread safety: stateless; safe to call from any context.
public enum ProfileValidation {
    /// Allowed number of characters (grapheme clusters) in a trimmed profile name.
    public static let nameLengthRange = 1...60
    /// Allowed auto-exit time in whole seconds: one minute to one day.
    public static let autoExitSecondsRange = 60...86_400
    /// Maximum length of a bundle identifier in characters.
    public static let bundleIdentifierMaximumLength = 255

    private static let minimumBundleIdentifierLabelCount = 2
    private static let labelSeparator: Character = "."
    private static let hyphen: Character = "-"

    /// Checks every profile-level rule and returns the profile with its name trimmed.
    ///
    /// - Throws: ``ProfileValidationError`` for the first rule that fails, in this order: name, duplicate steps,
    ///   display selections, wallpaper image URLs.
    public static func validate(_ profile: Profile) throws(ProfileValidationError) -> Profile {
        let name = try validatedName(profile.name)
        try validateUniqueSteps(profile.steps)
        for step in profile.steps {
            try validateStepContent(step)
        }
        return Profile(id: profile.id, name: name, steps: profile.steps, autoExit: profile.autoExit)
    }

    /// Trims whitespace and newlines and checks the length of the remaining name.
    ///
    /// - Throws: ``ProfileValidationError/emptyName`` or ``ProfileValidationError/nameTooLong(characterCount:)``.
    public static func validatedName(_ name: String) throws(ProfileValidationError) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= nameLengthRange.lowerBound else {
            throw .emptyName
        }
        guard trimmed.count <= nameLengthRange.upperBound else {
            throw .nameTooLong(characterCount: trimmed.count)
        }
        return trimmed
    }

    /// Checks a strict reverse-DNS bundle identifier: ASCII letters, digits and hyphens, at least two
    /// dot-separated labels, no label starting or ending with a hyphen, at most 255 characters.
    ///
    /// This is the allowlist that later keeps bundle identifiers out of AppleScript source unchecked.
    /// - Throws: ``ProfileValidationError/invalidBundleIdentifier(_:)``.
    public static func validateBundleIdentifier(_ value: String) throws(ProfileValidationError) {
        let labels = value.split(separator: labelSeparator, omittingEmptySubsequences: false)
        let isValid =
            value.count <= bundleIdentifierMaximumLength
            && labels.count >= minimumBundleIdentifierLabelCount
            && labels.allSatisfy(isValidBundleIdentifierLabel)
        guard isValid else {
            throw .invalidBundleIdentifier(value)
        }
    }

    /// Checks that an auto-exit time lies within ``autoExitSecondsRange``.
    ///
    /// - Throws: ``ProfileValidationError/autoExitOutOfRange(seconds:)``.
    public static func validateAutoExitSeconds(_ seconds: Int) throws(ProfileValidationError) {
        guard autoExitSecondsRange.contains(seconds) else {
            throw .autoExitOutOfRange(seconds: seconds)
        }
    }

    private static func validateUniqueSteps(_ steps: [ProfileStep]) throws(ProfileValidationError) {
        var seen: Set<ActionIdentifier> = []
        for step in steps {
            let (isNew, _) = seen.insert(step.actionIdentifier)
            guard isNew else {
                throw .duplicateStep(step.actionIdentifier)
            }
        }
    }

    private static func validateStepContent(_ step: ProfileStep) throws(ProfileValidationError) {
        guard case .wallpaper(let choice, let displays) = step else {
            return
        }
        if case .specific(let identifiers) = displays, identifiers.isEmpty {
            throw .emptyDisplaySelection
        }
        if case .image(let url) = choice, !url.isFileURL {
            throw .imageNotFileURL
        }
    }

    private static func isValidBundleIdentifierLabel(_ label: Substring) -> Bool {
        guard let first = label.first, let last = label.last, first != hyphen, last != hyphen else {
            return false
        }
        return label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == hyphen) }
    }
}
