# Design system

## Direction

One reference style, committed: **native macOS, Swiss-influenced**. Strong typographic hierarchy, flat surfaces, strict grid, one accent color used functionally, generous but intentional whitespace. It must feel like a well-made Mac app, not a web page in a window.

Banned: gradients, glow or colored shadows, custom blur or glassmorphism, emoji in UI or copy, decorative animation, stock illustrations, more than two typefaces, more than one accent color. System-provided window and popover materials supplied by AppKit are allowed because they are the platform; custom blur layers are not.

The visual character comes from: precise type scale, a distinctive but restrained accent, clear state design in the menu-bar icon, and a considered HUD. "Not boring" is achieved through craft in these details, not decoration.

## Typefaces

Two at most: SF Pro (system) for all text, SF Mono for hotkey display and numeric values (timers). No custom fonts in v1.

## Tokens

All values live in `DesignSystem/Tokens`. Views reference tokens only.

Spacing (4 pt grid): `xxs 2`, `xs 4`, `sm 8`, `md 12`, `lg 16`, `xl 24`, `xxl 32`.

Radius (at most 8): `small 4`, `medium 6`, `large 8`.

Type scale (points, system font): `caption 11 regular`, `body 13 regular`, `bodyEmphasis 13 semibold`, `title 15 semibold`, `headline 20 semibold`. Line height and tracking chosen per style and recorded in `DSTypography`.

Motion: `quick 0.12s`, `standard 0.2s`, ease-in-out. All animation honors Reduce Motion (disable or crossfade).

Colors are defined as named color sets in `Assets.xcassets` with Light and Dark variants and exposed as `DSColor.*`. Semantic names only:

| Token | Role |
|---|---|
| `surfaceBase` | Window background |
| `surfaceRaised` | Cards, rows |
| `separator` | Hairlines |
| `textPrimary`, `textSecondary`, `textDisabled` | Text hierarchy |
| `accent` | The single brand accent: selection, primary button, active state |
| `statusSuccess`, `statusWarning`, `statusDanger` | Functional status only |

Starting accent values (to be confirmed in the M2 design pass; contrast computed, not rendered): light `#2F5BEA` (about 5.5:1 on white), dark `#7C9BFF` (about 6:1 on `#1E1E1E`). Every text/background pair must reach 4.5:1; non-text UI elements 3:1. Contrast is verified for both appearances before a token is accepted.

## Appearance (theme)

Three user choices in Settings > Appearance: **System** (default), **Light**, **Dark**.

- System = follow macOS automatically, including live switching while the app runs.
- Light / Dark = forced regardless of the system.
- Implementation: `AppearancePreference` enum in `DesignSystem/Theme`, persisted via the typed preferences wrapper. `ThemeController` applies it by setting `NSApp.appearance` (`nil` for System, `.aqua` / `.darkAqua` for forced) so every window, the menu-bar popover, and the HUD follow. SwiftUI views additionally read `colorScheme` from the environment; they never branch on the preference itself.
- All colors resolve through the asset catalog. No `if colorScheme == .dark` in feature code.
- Test: switching preference updates all open windows without relaunch; System mode follows the OS toggle live.

## Localization

- Languages: English (source) and Russian. Language preference: System (default), English, Russian, set in Settings > General. Applying a language override that differs from the system may require relaunch; if so the UI says so explicitly (`UNVERIFIED` behavior, decide in M3 after testing).
- Strings live in `Resources/Localizable.xcstrings`. Keys are semantic and namespaced: `settings.profiles.empty.title`. No English sentence as a key.
- Code access goes through typed namespaces in `App/Sources/Localization/` (`L10n.Settings.profilesEmptyTitle`) returning `LocalizedStringResource`. Views and view models never contain raw string literals for UI text.
- Plurals use String Catalog plural variations. Dates, numbers, and durations use `Formatter`/`FormatStyle`, never manual formatting.
- Every string has a translator comment describing context.
- Pseudo-test: run once with the longest-string stress locale and with Russian; no truncation in the menu popover, settings sidebar, or HUD.

## Components (DesignSystem/Components)

Each component: documented purpose, all states implemented (default, hover, pressed, focused, disabled; loading and error where relevant), previews in Light and Dark, accessibility labels.

Initial set: `DSButton` (primary, secondary, destructive), `DSToggleRow`, `DSSectionHeader`, `DSRow` (selectable list row), `DSEmptyState`, `DSStatusBadge`, `DSHotkeyField` (wraps recorder), `DSColorSwatchPicker`, `DSInlineMessage`.

Rules: no component knows about profiles or sessions. Components take plain values and closures.

## Surfaces

### Menu-bar icon
Monochrome template image, three states: idle, active, degraded (needs attention). State change must be distinguishable without color (shape change), so it also works with the menu bar auto-hidden and on any wallpaper. Icon assets are vector (PDF) in the asset catalog.

### Menu-bar popover (window style)
Width about 320 pt. Top: current state line (Inactive / Active: profile name, with elapsed time). Middle: profile list; click activates; the active profile shows a stop control. Bottom: Settings, Quit. Keyboard navigable, VoiceOver labeled.

### HUD
Borderless, non-activating panel centered on the active display, about one second, fades out, no focus steal, not capturable as a blocking window, honors Reduce Motion. Content: icon, profile name, state word. Never appears in an inactive or failed state silently: failures show a danger HUD with the action name.

### Settings window
Sidebar layout: Profiles, General, Appearance, Permissions. Profiles is master-detail (list left, editor right) with an explicit empty state ("Create your first profile"). Standard macOS window behavior, remembers size and last pane.

### Onboarding
Single window, linear steps: Idea, Hotkey, Launch at login, Permissions, First profile. Each step skippable except where a permission is required for the feature; every skipped item remains reachable in Settings.

## Accessibility

- Contrast as above. Focus ring visible everywhere. Full keyboard navigation. VoiceOver labels on icon-only controls. Minimum click target 24 pt on macOS (44 pt for any touch-like affordance; none planned).
- Respect Reduce Motion, Increase Contrast, and Reduce Transparency.
- No state conveyed by color alone.

## Definition of done for any UI work

Previews for Light and Dark. Verified in System, Light, Dark modes. Verified in English and Russian. All interactive states present. No literals outside tokens and L10n. Screenshot of each new surface in both appearances attached to the PR.
