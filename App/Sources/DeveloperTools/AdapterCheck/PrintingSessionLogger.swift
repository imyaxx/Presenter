#if DEBUG
import Foundation
import ModeKit

/// A ``SessionLogger`` that writes each event as a JSON line to the tool's output and forwards it to another logger
/// (the real `OSSessionLogger`). The line includes the private detail: it stays in a local file.
struct PrintingSessionLogger: SessionLogger {
    struct Line: Encodable, Equatable, Sendable {
        let type = "session"
        let level: String
        let text: String
        let detail: String?
    }

    private let output: CheckOutput
    private let forwardedTo: any SessionLogger

    init(output: CheckOutput, forwardingTo logger: any SessionLogger) {
        self.output = output
        forwardedTo = logger
    }

    static func line(for event: SessionEvent) -> Line {
        let message = SessionLogMessage(event)
        let level =
            switch message.level {
            case .info: "info"
            case .error: "error"
            }
        return Line(level: level, text: message.publicText, detail: message.privateDetail)
    }

    func log(_ event: SessionEvent) {
        output.emit(Self.line(for: event))
        forwardedTo.log(event)
    }
}
#endif
