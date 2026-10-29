# Liquid Glass review (Axiom)

Installed skill to load in later sessions: `ios-liquid-glass`.

Companion docs in the same folder: `adopting-liquid-glass.md`, `applying-to-custom-views.md`, `reference.md`, `landmarks-toolbar-glass.md`.

This is a macOS 26 menu-bar HUD, not an iOS app. Rules that are iOS-only are called out and are not gaps.

Compared against the live views, `HUDMetrics`, and `notes/references/launcher-hud.jpg`. No restyle in this pass.

## Accepted for this plate

One `NSGlassEffectView` sits inside `NSGlassEffectContainerView` at spacing 0. There is no SwiftUI `GlassEffectContainer`. Agent, Screen, chips, and the shortcut badge are fills inside `contentView`, not sibling glass and not `.buttonStyle(.glass)`. `effectIsInteractive` stays off on the flag-off plate because a click flexes the 560-point plate. In New UI only the pills are interactive; the capsule is a text surface and does not flex. The flag-off plate is not interactive either. Do not add `glassEffect` or turn the flag on to match the skill.

## Gaps

### 5. Hardcoded corner radius, not concentric to the plate

**Where:** `HUDMetrics.cornerRadius = 24` on the card (`HUDController.clipHosting`, `CardGlassView`) and on Settings cards. Highlighted controls use `HUDMetrics.pillInset` (8) on a capsule fill.

**Skill:** Harmony = concentric corners. Custom glass should use `.rect(cornerRadius: .containerConcentric)` / `ConcentricRectangle`, not a one-size radius copied onto inner cards.

Settings cards reuse the HUD’s 24pt radius on a 720×680 window, so they are not concentric to the window.

### 6. Settings uses solid custom cards instead of grouped Form / system lists

**Where:** `SettingsView.SettingsCard` and `DebugView.debugCard` fill `Color(nsColor: .controlBackgroundColor)`. Chat pane is a `Table` plus caption, not a `Form`. Endpoint editor is a custom `VStack` sheet (`SettingsView.EndpointEditorView`). Sidebar is a `List` with `.scrollContentBackground(.hidden)` and a `Divider`, not `NavigationSplitView`.

**Skill (`adopting-liquid-glass.md`):** Prefer standard SwiftUI / AppKit components so bars, sheets, and controls pick up Liquid Glass. Remove custom backgrounds on navigation and chrome; they overlay or block the material and the scroll-edge effect. Use `Form` with `.grouped` for layout metrics (larger rows, padding, section radius). Section headers use title-style capitalization via `Section`. Sheets: drop custom background views; on iOS also `.scrollContentBackground(.hidden)` on a Form and `.presentationDetents` (those two are iOS sheet chrome — see below).

The Settings window (`HUDController.makeSettingsWindow`) is a titled, closable `NSWindow` with `safeAreaRegions = []` and no resize. The same adopting doc: support arbitrary window sizes; keep safe areas so title-bar / window controls can sit correctly.

### 7. The prompt kills the focus ring

**Where:** `PromptField` / `PromptHostView` (`focusRingType = .none` on field and scroll).

**Skill:** System glass adapts to focus. Use standard controls and the system focus APIs. `reference.md` lists `@Environment(\.colorSchemeContrast)` next to Reduce Transparency / Reduce Motion.

Reduce Transparency is wired (`HUDController` rebuilds to `SolidCardView`). Resigning key does not change the capsule fill. The prompt has no system focus treatment.

### 8. Typography ignores Dynamic Type

**Where:** `PromptLayout.fontSize = 16` (`NSFont.systemFont`), `HUDView` `.font(.system(size: 9…16))` on chips, status, toolbar, shortcut, history chevron.

**Skill:** Accessibility essentials include Dynamic Type. The installed skill has no separate type scale; it does not ask for a custom display face.

Hardcoded point sizes will not track the user’s text size. Reply body uses `.body` / `.caption`, which is the exception.

### 9. Missing accessibility labels on icon controls

**Where:** `HUDView` — submit, history chevron, chip dismiss, Ask/Agent, Screen, Add context, shortcut badge. Only the logo and the mic `.help` string are labeled.

**Skill:** Provide an accessibility label for every icon. VoiceOver / Voice Control need the label even when the UI shows a symbol.

### 10. App icon is a flat PNG set, not Icon Composer layers

**Where:** `AIHUD/Assets.xcassets/AppIcon.appiconset` (raster mac sizes only).

**Skill:** When to use includes Icon Composer. `adopting-liquid-glass.md`: layered icons, let the system apply mask/blur/light, preview default / dark / clear / tinted.

Not HUD chrome. Still a documented Liquid Glass gap for the Dock/About icon.

## iOS-only (do not treat as HUD work)

- **UIKit haptics** (`UIImpactFeedbackGenerator` in `SKILL.md`). macOS equivalent is optional `NSHapticFeedbackManager`; the skill’s UIKit snippet does not apply.
- **Floating `TabView` / `tabBarMinimizeBehavior` / `Tab(role: .search)`.** No tab bar.
- **Sheet detents, half-sheet insets, `navigationTransition(.zoom)`.** macOS Settings is a window + modal sheet, not an iPhone sheet stack.
- **44×44 pt touch targets.** Pointer UI. Chip dismiss and the 22×24 pt history/mic hits are still unlabeled and small, but the 44 pt rule itself is iOS.
- **tvOS focus glass.** Not this app.

## What already matches

- Card material is real `NSGlassEffectView` inside `NSGlassEffectContainerView` (spacing 0), clear vs regular mapped from Appearance Glass/Matte (`HUDMaterial.effectStyle`). Reference card is a clear floating plate. Highlighted Agent and Screen are `HUDSelectionFill`, not a second glass view.
- Reduce Transparency swaps the card to a solid plate (`HUDMaterial.usesSolidCard`). Reduce Motion zeroes panel fade (`HUDPanel`).
- Content (prompt, reply) is not itself glass; it sits in the plate. That matches “glass frames, does not obscure.”
- Idle metrics (560 width, 52 pt rows, left cluster / trailing shortcut) already follow `launcher-hud.jpg`. Do not restyle that layout to look like an iOS toolbar.

## macOS applicability

Researched 2026-09-27 against current Apple docs. The skill is titled iOS and its snippets are iOS-shaped. Liquid Glass itself is not.

**Verdict: partly.** Design principles and the core glass APIs apply on macOS 26+ (this machine is darwin 27 / macOS 26-era, SDK `MacOSX27.sdk`). iOS chrome in the skill (floating tab bar, sheet detents, UIKit haptics, 44 pt) does not. WWDC 2025 *Meet Liquid Glass* (219) says the same principles apply on iPad and Mac. *Adopting Liquid Glass* is written for SwiftUI, UIKit, **and AppKit**. The skill’s `reference.md` lists macOS Tahoe 26 but omits WWDC 310 (*Build an AppKit app with the new design*). No WWDC 2026 session changes that split.

| Rule | Scope | macOS API |
|------|--------|-----------|
| Nearby glass in one container | **Applies.** SwiftUI `GlassEffectContainer` is iOS 26+, **macOS 26+**. Same job in AppKit. | `NSGlassEffectContainerView` (macOS 26+). Merges similar descendant glass within `spacing`; batches render passes. |
| Interactive glass | **Applies, split by generation.** SwiftUI `Glass.interactive()` is macOS 26+. AppKit flag is later. | `NSGlassEffectView.effectIsInteractive` is **macOS 27+** (in `MacOSX27.sdk`; absent from `MacOSX26.5.sdk`). Default `NO`. Docs: enable when the glass is the background or container of interactive controls. |
| Toolbar grouping / glass buttons | **Shared principle; different chrome.** `ToolbarSpacer` is iOS 26+, **macOS 26+**. Skill’s `.topBarTrailing` is iOS/iPad. A floating HUD does not need `NSToolbar`. | SwiftUI: `ToolbarSpacer`, `ToolbarItemGroup`, `.buttonStyle(.glass)` / `.glassProminent` (macOS 26+). AppKit: `NSToolbarItem.Identifier.space` / `NSToolbarItemGroup`, `NSButton.BezelStyle.glass` (macOS 26+). |
| Regular vs clear | **Applies.** Do not mix. Clear is for media-rich backgrounds with dimming (WWDC 219). | SwiftUI `Glass.regular` / `.clear` / `.identity` (macOS 26+). AppKit `NSGlassEffectView.Style.regular` / `.clear` (macOS 26+). |
| Nested glass plates | **Applies (design, not iOS-only).** WWDC 219: avoid glass on glass; overlays should be fills, transparency, vibrancy. *Adopting*: do not layer Liquid Glass on itself. A container merges **nearby siblings**; it does not license stacking plates. | Same APIs as the container row. Put content in `contentView` / `.glassEffect` content, not a second `NSGlassEffectView` on top. |
| Haptics | **iOS only** for the skill snippet. | `UIImpactFeedbackGenerator` is UIKit. Optional Mac trackpad API is `NSHapticFeedbackManager`. Not a Liquid Glass requirement. |
| Tab bars | **iOS/iPad primarily.** *Adopting* calls `tabBarMinimizeBehavior` out as iOS. Mac navigation is sidebar / toolbar. | No AppKit tab-bar glass API for a menu-bar HUD. `TabView` + `sidebarAdaptable` can become a sidebar on Mac; that is not this app. |
| Sheets | **Shared: drop custom sheet backgrounds.** **iOS only:** detents, half-sheet insets, zoom `navigationTransition`. | macOS sheet is a window / `.sheet` / `NSAlert.beginSheetModal`. |
| 44 pt targets | **iOS only.** HIG Accessibility: iOS/iPadOS default 44×44, min 28×28. macOS default **28×28**, min **20×20**. | Pointer UI. Do not import the skill’s 44 pt rule. |

Sources: *Adopting Liquid Glass*; *Applying Liquid Glass to custom views*; WWDC 219 / 310; `NSGlassEffectView.h` (26.5 vs 27); SwiftUI DocC availability on `GlassEffectContainer`, `glassEffect`, `ToolbarSpacer`; HIG Layout (Liquid Glass “consistent across iOS, iPadOS, and macOS”); HIG Accessibility control-size table; HIG Playing haptics.
