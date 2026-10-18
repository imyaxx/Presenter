import Foundation

extension StoreError {
    /// Maps an error thrown by ``SessionStore``, which throws only `StoreError` (documented, not typed).
    init(sessionStoreError error: any Error) {
        if let storeError = error as? StoreError {
            self = storeError
        } else {
            self = .ioFailure(fileName: SessionFile.fileName, reason: String(describing: type(of: error)))
        }
    }
}
