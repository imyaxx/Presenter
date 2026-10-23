import SwiftUI

/// A dismissible notice under the state line.
struct MenuBarNoticeView: View {
    let notice: MenuBarNotice
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                ForEach(L10n.Notices.lines(notice), id: \.self) { line in
                    Text(verbatim: line)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(L10n.Menu.dismissNotice))
        }
    }
}
