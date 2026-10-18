import ModeKit
import os

/// The real ``SessionLogger``: `os.Logger`, category `session` (docs/01, docs/03).
///
/// `info` for state changes and successful steps, `error` for failures. The text comes from ``SessionLogMessage``:
/// its public part is logged as `.public`, its detail (reasons that may contain paths) as `.private`.
///
/// Threading: a value type; `os.Logger` is thread-safe and does not block.
struct OSSessionLogger: SessionLogger {
    static let category = "session"

    private let logger: Logger

    /// - Parameter subsystem: The app's bundle identifier, read from `Bundle.main` by the composition root.
    init(subsystem: String) {
        logger = Logger(subsystem: subsystem, category: Self.category)
    }

    func log(_ event: SessionEvent) {
        let message = SessionLogMessage(event)
        switch (message.level, message.privateDetail) {
        case (.info, nil):
            logger.info("\(message.publicText, privacy: .public)")
        case (.info, let detail?):
            logger.info("\(message.publicText, privacy: .public): \(detail, privacy: .private)")
        case (.error, nil):
            logger.error("\(message.publicText, privacy: .public)")
        case (.error, let detail?):
            logger.error("\(message.publicText, privacy: .public): \(detail, privacy: .private)")
        }
    }
}
