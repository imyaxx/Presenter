import Foundation

/// Typed access to the user-visible strings in `Localizable.xcstrings`.
///
/// One nested namespace per feature, each in its own `L10n+<Feature>.swift` file.
/// Views and view models never contain string literals for UI text.
enum L10n {}
