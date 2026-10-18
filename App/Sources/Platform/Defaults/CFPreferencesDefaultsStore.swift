import CoreFoundation
import Foundation
import ModeKit

/// The real ``DefaultsStore``: `CFPreferences` for the current user and any host (ADR-040, spike S1).
///
/// The domain `"NSGlobalDomain"` maps to `kCFPreferencesAnyApplication`. `CFPreferencesSynchronize` runs before every
/// read and after every write or removal, so values written by another process are seen and writes reach disk
/// (cfprefsd caches per process). Access to `com.apple.finder` and `com.apple.dock` from the app is unverified
/// (docs/07).
///
/// Threading: a value type; `CFPreferences` is thread-safe. Calls do not wait on another process beyond cfprefsd.
struct CFPreferencesDefaultsStore: DefaultsStore {
    static let globalDomain = "NSGlobalDomain"

    /// The `CFPreferences` application identifier for a domain name.
    static func applicationID(for domain: String) -> CFString {
        domain == globalDomain ? kCFPreferencesAnyApplication : domain as CFString
    }

    /// - Throws: ``DefaultsError/unsupportedValueType(_:)`` for a type other than a boolean or an integral number,
    ///   or ``DefaultsError/failed(reason:)`` when synchronizing fails.
    func value(for key: DefaultsKey) async throws -> DefaultsValue? {
        let application = Self.applicationID(for: key.domain)
        try synchronize(application)
        guard
            let stored = CFPreferencesCopyValue(
                key.name as CFString,
                application,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost,
            )
        else {
            return nil
        }
        return try Self.defaultsValue(from: stored, for: key)
    }

    /// - Throws: ``DefaultsError/failed(reason:)`` when synchronizing fails.
    func set(_ value: DefaultsValue, for key: DefaultsKey) async throws {
        try write(Self.propertyList(for: value), for: key)
    }

    /// Removing an absent key succeeds.
    ///
    /// - Throws: ``DefaultsError/failed(reason:)`` when synchronizing fails.
    func remove(_ key: DefaultsKey) async throws {
        try write(nil, for: key)
    }

    private func write(_ value: CFPropertyList?, for key: DefaultsKey) throws {
        let application = Self.applicationID(for: key.domain)
        let name = key.name as CFString
        CFPreferencesSetValue(name, value, application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        try synchronize(application)
    }

    private func synchronize(_ application: CFString) throws {
        guard CFPreferencesSynchronize(application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw DefaultsError.failed(reason: "CFPreferencesSynchronize failed for \(application)")
        }
    }

    /// Maps by Core Foundation type identifier, not by `NSNumber` bridging, which would turn a boolean into 1 or 0.
    static func defaultsValue(from stored: CFPropertyList, for key: DefaultsKey) throws -> DefaultsValue {
        let typeID = CFGetTypeID(stored)
        if typeID == CFBooleanGetTypeID() {
            // The type identifier check above makes this cast always succeed.
            guard let boolean = stored as? Bool else {
                throw DefaultsError.unsupportedValueType(key)
            }
            return .bool(boolean)
        }
        if typeID == CFNumberGetTypeID(), let number = stored as? NSNumber, !CFNumberIsFloatType(number as CFNumber) {
            return .integer(number.intValue)
        }
        throw DefaultsError.unsupportedValueType(key)
    }

    private static func propertyList(for value: DefaultsValue) -> CFPropertyList {
        switch value {
        case .bool(let boolean): boolean ? kCFBooleanTrue : kCFBooleanFalse
        case .integer(let integer): integer as CFNumber
        }
    }
}
