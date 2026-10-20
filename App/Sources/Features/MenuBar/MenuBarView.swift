import SwiftUI

/// The menu-bar popover (docs/04): the state line, a notice, the content for the state, and the footer. System
/// controls, fonts and colors only; `feat/design-system-foundation` restyles it without changing behavior.
struct MenuBarView: View {
    /// The popover width of docs/04; text wraps inside it.
    static let width: CGFloat = 320

    let model: MenuBarViewModel
    let version: String?
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            MenuBarStateLine(presentation: model.presentation)
            if let notice = model.notice {
                MenuBarNoticeView(notice: notice, dismiss: model.dismissNotice)
            }
            Divider()
            MenuBarContentView(model: model)
            Divider()
            MenuBarFooter(model: model, version: version, quit: quit)
        }
        .padding()
        .frame(width: Self.width)
        .task { await model.popoverDidOpen() }
    }
}
