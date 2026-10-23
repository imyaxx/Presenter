import AppKit
import Foundation
import Testing

@testable import PresenterApp

/// Every row of controls in the menu-bar popover fits its width in English and Russian, measured with the system font.
///
/// The constants were measured on macOS 27.0.1 from the Q9 screenshots (2026-10-21): the content starts 16 pt inside
/// the popover, a bordered button is 25 pt wider than its label, and controls in a row are 8 pt apart. The model
/// reproduces what the screenshots showed: Retry Restore and Discard Session File… fit side by side in English and
/// were truncated in Russian, so they are now stacked (`MenuBarAttentionView`).
@MainActor
struct MenuBarLabelWidthTests {
    private enum Control {
        case bordered(LocalizedStringResource)
        case borderless(LocalizedStringResource)
        case caption(LocalizedStringResource)
    }

    private nonisolated static let languages = ["en", "ru"]
    private static let contentWidth = MenuBarView.width - 2 * 16
    private static let borderedButtonInset: CGFloat = 25
    private static let rowSpacing: CGFloat = 8
    private static let captionFontSize: CGFloat = 10

    /// Each row as laid out; a control beside wrapping text, such as Stop beside the profile name, is its own row.
    private static let rows: [[Control]] = [
        [.bordered(L10n.Menu.stop)],
        [.bordered(L10n.Menu.retryRestore)],
        [.bordered(L10n.Menu.discard)],
        [.bordered(L10n.Menu.discardCancel), .bordered(L10n.Menu.discardConfirm)],
        [.borderless(L10n.Menu.showProfiles)],
        [.caption(L10n.Menu.version("0.1.0")), .borderless(L10n.Menu.quit)],
    ]

    private static func text(_ resource: LocalizedStringResource, in language: String) -> String {
        var localized = resource
        localized.locale = Locale(identifier: language)
        return String(localized: localized)
    }

    private static func textWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        return (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    private static func width(of control: Control, in language: String) -> CGFloat {
        switch control {
        case .bordered(let resource):
            textWidth(text(resource, in: language), fontSize: NSFont.systemFontSize) + borderedButtonInset
        case .borderless(let resource):
            textWidth(text(resource, in: language), fontSize: NSFont.systemFontSize)
        case .caption(let resource):
            textWidth(text(resource, in: language), fontSize: captionFontSize)
        }
    }

    private static func width(of row: [Control], in language: String) -> CGFloat {
        row.map { width(of: $0, in: language) }.reduce(0, +) + rowSpacing * CGFloat(row.count - 1)
    }

    @Test(arguments: languages)
    func everyRowFitsThePopover(language: String) {
        for row in Self.rows {
            #expect(Self.width(of: row, in: language) <= Self.contentWidth)
        }
    }

    @Test
    func theRussianLabelsAreResolvedFromTheCatalog() {
        #expect(Self.text(L10n.Menu.stop, in: "ru") != Self.text(L10n.Menu.stop, in: "en"))
    }

    @Test
    func theAttentionButtonsSideBySideFitInEnglishButNotInRussian() {
        let sideBySide: [Control] = [.bordered(L10n.Menu.retryRestore), .bordered(L10n.Menu.discard)]

        #expect(Self.width(of: sideBySide, in: "en") <= Self.contentWidth)
        #expect(Self.width(of: sideBySide, in: "ru") > Self.contentWidth)
    }
}
