# Error lip

Plan only. Do not implement in the pass that writes this file. `notes/plan.md` stays the pointer to the product plan.

The in-card error line is the wrong object. `HUDView.settingsLine` sits between the hairline and the toolbar, `HUDLayout.cardHeight(hasErrorLine:)` adds 28pt to the glass plate, and `HUDController.syncFrame` stretches that plate so Agent through mic stay inside. Capture: `notes/captures/hud-error-inside.png`. That keeps the toolbar in the glass, and it also makes the error a second row of the card. The attached Cursor-style reference is a lip: a second rounded band peeking out from under the plate, with the toolbar still in the 108pt idle card.

Visual spec for the lip: the attached PNG (chat asset `image-56be4827-1fc0-47e2-819c-60c1b4a74fe1.png`). Idle card spec remains `notes/references/launcher-hud.jpg`.

## 1. What the lip is

Measured on the reference (1024x342, card body 922px wide). Scaled to our 560pt card.

**Placement.** One outer rounded rect (window-sized, 24pt continuous) with the glass plate sitting on top. The visible lip is the bottom of that outer shape, including the plate's bottom corner notches. It is not a second pill. There is no empty air between card and lip.

**Overlap.** None. The warning is its own bar under the plate. It does not tuck into the card corner, and it does not change the plate's continuous border.

**Size.**

- Visible peek below the card is 28pt (`lipVisible`). The window grows by that amount. The bar does not extend up behind the plate.
- The warning is the card width minus 24pt on each side (`lipInset`). No wings. The plate border stays the continuous 24pt corner.
- The lip's own bottom corners are 16pt (`lipCorner`), not the plate's 24pt. The band is inset, so the window mask is the plate plus that narrower rect. The plate's 24pt mask alone would crop the lip.

**Chrome.** Near-black fill sampled from the reference, about RGB(22, 16, 18) fading to (38, 20, 24) at the bottom. Not a 0.30 systemRed overlay on windowBackgroundColor; that read as a maroon bar. Leading SF Symbol `exclamationmark.circle` in dusty rose (not system red, not a filled stop badge). Message in 13pt system, same rose, one line, leading, truncates. Trailing `xmark` to dismiss, plain button, 11pt, light white at ~0.58, optically aligned with `HUDMetrics.inset` (20). Horizontal content inset matches the card (20). Vertical alignment is centered in the visible 28pt peek.

**Copy.** Keep our specific sentences. The reference string "Something went wrong. Please try again." is the look, not the catalog. Debug Failed still uses `DebugRouting.timedOut` ("The request timed out."). Request failed still uses "The request failed." Sign-in, missing key, missing model, missing endpoint, mic, speech, and screen copy stay as they are.

**What must not move.** Prompt row, hairline, chips, history, and the toolbar (Agent, Screen, Add context, shortcut, mic) stay inside the glass plate. The idle card without a reply is still 560 by 108 against `launcher-hud.jpg`. The lip never pushes those controls down or clips them.

## 2. Which messages use it

One lip, one message. Pull the same sources `showsErrorLine` already unions, then pick with this order (first match wins):

1. `session.phase == .failed(message)` (request timeout, request failed, on-device failed, attachment errors that already call `session.fail` / `reportAttachmentError`, send blocked after Submit)
2. `store.blockingMessage` while `phase == .composing` (choose a chat model, add an API key, add a model id, sign in to ChatGPT, finish the vision model)
3. `screenNotice` (Allow Screen Recording in System Settings, The screen capture failed)
4. non-empty `voiceStatus` (mic denied, speech denied, speech model missing or downloading, microphone capture failed)

**Moves to the lip.** All of the above. Remove `settingsLine` from the `HUDView` VStack. Do not leave a duplicate gray line in the card.

**Stays on the card.** Prompt, "Ask anything..." / "Listening...", idle mark or waveform, chips, hairline, compact or expanded reply, Thinking, toolbar. Dictation animation stays in the prompt-row slot. Voice permission is requested from Settings, not from a new in-card control.

**Clicks.** The X only dismisses (section 3). The rest of the lip is still a hit target when the copy has somewhere to go:

- Failed / blocking copy that today calls `model.openSettings` still opens Settings.
- `voiceStatus` that `VoiceStatusCopy.systemSettingsURL` maps (mic and speech) still opens Privacy & Security. Keep that helper. The existing `voiceStatusOpensTheMatchingPrivacyPane` test stays.
- `screenNotice` permission copy still opens Screen Recording in System Settings (`openScreenSettings`).
- Copy with no URL (capture failed, speech model missing, downloading, generic request failure) is not a navigation button. X still works.

If two sources are set, show the higher one. Debug can still set them independently; the live card shows one lip.

## 3. Layout rules

The glass plate is the card. The lip is not part of the card's height.

**Card.** `HUDLayout.cardHeight` no longer takes `hasErrorLine`. Idle floor stays `HUDMetrics.minCardHeight` (108). Chips, multiline, and a reply still grow the card downward. `measuredHeight()` is the hosting fitting size of HUD content only, floored at 108, then run through `settledHeight` the same way as today.

**Window.** `windowHeight(card:hasLip:) = card + (hasLip ? lipVisible : 0)`. `lipVisible` is 28. The panel's content view is that taller rect. The glass (or solid) plate is the card rect, pinned to the top of the content view. The lip view is the full window rect so its continuous 24pt corners are the outer silhouette. A hole in the plate rect keeps the fill out of the glass.

AppKit y is bottom-up. Glass frame `y = hasLip ? lipVisible : 0`, height `card`. Lip frame is the wrapper bounds. Z-order: lip behind, plate on top.

**Top edge.** Keep `HUDLayout.framePinnedTop` / `HUDPanel.resizePinnedTop`. Showing the lip grows the window downward. Dismissing the X shrinks it the same way. The top of the card does not move.

**Wiggle.** `syncFrame` today feeds the panel height (card plus the in-card 28pt) into `settledHeight`, and `HUDView` uses `cardHeight(hasErrorLine:)` as `minHeight`. After this change, settle the card height only. Then add `lipVisible`. Single-line typing must not reintroduce the 1pt `fittingSize` step. Keep `HUDLayout.heightFlicker` (1) and the "delta smaller than a line, keep prior" rule on the card. Do not let the lip flag flap during a keystroke. `singleLineKeystrokeFlickerDoesNotChangeHeight` still has to pass, including the jump from idle 108 to a window that includes the lip when an error actually appears.

**Dismiss.** New `HUDModel.dismissLip()`. X calls it.

- Clear the visible source: `failed` goes back to `.composing` and `errorMessage = nil`; `voiceStatus` / `screenNotice` nil out if that was the shown source.
- Set a `lipDismissed` flag so a still-true `blockingMessage` does not immediately put the lip back. The next `session.fail`, `reportAttachmentError`, `reportScreenFailure`, or a new `voiceStatus` assignment clears that flag and shows the lip again. Submit already calls `session.fail` on a blocked route, so a retry after dismiss reopens the lip.
- Do not open Settings. Do not touch Keychain, `chat.endpoints`, `chat.defaultEndpointID`, model ids, or Debug enablement.
- Escape / click-outside still uses `HUDModel.dismiss`, which already clears voice and screen notices and may hide the card. Lip X does not hide the card.

`HUDController.syncFrame` must stop assigning the full window bounds to `glass` and to `hosting`. Those two stay card-sized. The container / wrapper / panel content view take the window size. Today's autoresizing that stretches `CardGlassView` and `SolidCardView` to the panel is what would turn the lip into more card.

## 4. Material

The card is one `NSGlassEffectView` inside `NSGlassEffectContainerView` (`HUDController.mount`). Interactive glass stays off. `notes/liquid-glass-review.md` and WWDC 219: do not stack a second glass plate, do not put glass on glass, overlays are fills. Agent and Screen are already capsules, not nested `NSGlassEffectView` pills. The lip follows that rule.

**Do not** give the lip its own `NSGlassEffectView`, SwiftUI `.glassEffect`, or `.buttonStyle(.glass)`. **Do not** put the lip in `CardGlassView.contentView` or in the SwiftUI tree that `clipHosting` rounds and clips. That is how it became an in-card row.

**Do** add a non-interactive sibling in the container wrapper, behind the plate: an `NSView` (or a hosting view whose only job is this band) with `wantsLayer`, continuous corner radius 24, masksToBounds. The view is the outer rounded shape. Fill is the sampled near-black (22, 16, 18) to (38, 20, 24), with a hole in the plate rect so the glass does not pick up red. Type and icon use the dusty rose from the reference glyphs. The X is light, not red.

Reduce Transparency keeps `SolidCardView` as the plate. Same sibling lip under it, same fill, no glass. Matte vs clear on the card does not change the lip.

Hit testing: the overlap belongs to the card (toolbar stays clickable). The visible 28pt belongs to the lip (message and X). Clicks on the lip are inside `panel.frame`, so they are not click-outside.

## 5. Debug panel

Existing Status and Phase buttons that already produce an error line must produce the lip, with the same copy, without clearing keys or endpoints.

Shows the lip: Failed, Request failed, Missing endpoint, Missing key, Missing model, Sign in, Mic denied, Speech denied, Generic failure.

Does not show the lip: Empty, Draft, Waiting, Streaming, Finished, Second turn, Listening, Clear status, Reset to idle, logo overrides, Arm Screen / Window.

`DebugRouting.apply` can stay as it is for those commands. `clearStatus` already drops voice and screen notices only. Lip X is not Debug Reset and is not Clear status. A test must prove dismiss does not write `chat.endpoints`, does not delete `api-key.<uuid>`, and does not flip `debug.enabled`.

`--debug-state=failed` and the other error states still drive the live card. After implementation, capture the lip (do not commit `notes/captures/`) and compare with the attached reference and `launcher-hud.jpg`. Record the path in `notes/README.md`.

## 6. Tests to write first

Pure Swift Testing. No snapshots, no XCUI. Red, then green. Put layout in `HUDLayout` and message picking in a small `HUDErrorLip` helper so tests do not need a panel.

Rewrite `cardHeightGrowsByTheErrorLine`. It should fail until the card floor ignores the lip.

Cover:

- Lip message is nil when composing with no blocking copy, no screen notice, and no voice status.
- Lip message is non-nil for `.failed`, for composing plus `blockingMessage`, for `screenNotice`, and for non-empty `voiceStatus`, using the priority in section 2.
- `dismiss` of that message yields nil. A dismissed blocking copy stays hidden until a new `fail` (or the other assign paths) arrives.
- `HUDLayout.cardHeight` with and without an error equals `HUDMetrics.minCardHeight` for the idle card. A reply still grows the card. The error does not.
- `HUDLayout.windowHeight(card:hasLip:)` equals the card when there is no lip, and `card + lipVisible` when there is. `lipHeight == lipVisible`. `lipFrame` is inset 24pt on each side and its top is the bottom of the plate.
- `settledHeight` still ignores a 1pt single-line flicker on the card. Settling 108 vs 108+28 when `hasLip` becomes true is allowed and must change the window, not the card.
- `framePinnedTop` with a taller window lowers `origin.y` by the delta; shrinking raises it. Top edge implied by `origin.y + height` stays put.
- Dismiss does not clear a saved URL, model id, or API key in a UserDefaults suite / secret slot used by the test.
- `VoiceStatusCopy.systemSettingsURL` still returns Microphone and Speech Recognition panes for those two sentences, and nil for capture-failed and model copy.

Run `xcodebuild test -scheme Axiom -destination 'platform=macOS'`.

## 7. Out of scope

- Restyling Agent, Screen, Add context, the shortcut badge, or the mic.
- A second interactive glass plate, `.buttonStyle(.glass)` on the lip, or putting the lip inside `NSGlassEffectView.contentView`.
- Replacing our error sentences with the reference's generic line.
- Snapshot tests, XCUI, or committed captures.
- Changing `notes/plan.md`.
- Tool calls, a markdown renderer for the lip, wrapping the error onto two lines, or animating the lip beyond the panel's existing fade.
- Opening Settings or System Settings from the X.
- Changing click-outside, Keep the card up, or the nonactivating panel.
- Debug buttons beyond wiring the current error states through the new layout.

## Implementation sketch (later pass)

1. Tests in `AIHUDTests/ChatLogicTests.swift` (layout and lip picking) and a dismiss-does-not-clear-secrets case next to the existing endpoint tests. Fail them.
2. `HUDLayout` in `AIHUD/HUD/HUDMetrics.swift`: `lipHeight`, `lipOverlap`, `lipVisible`, `windowHeight(card:hasLip:)`. Stop adding the error to `cardHeight`.
3. `HUDErrorLip` pure helper: message, tap action (settings / voice / screen / none), dismiss.
4. `HUDView`: delete the in-VStack `settingsLine`. Idle `minHeight` is the card only. New `ErrorLipView` is not in that VStack.
5. `HUDController.mount` / `syncFrame`: wrapper taller than the plate; lip sibling behind `CardGlassView` / `SolidCardView`; hosting clipped to the card rect. Stop setting `glass.frame` and `hosting.frame` to the full window.
6. `HUDModel.dismissLip()` plus `lipDismissed`. Wire X. Keep `openSettings` / `openVoiceSettings` / `openScreenSettings` on the message.
7. Debug: no new commands required if Failed and the Status buttons already set the same fields. Confirm they show the lip. Dismiss must not call `DebugRouting.apply("reset")`.
8. Live capture vs the attached reference and `notes/references/launcher-hud.jpg`. Note the path in `notes/README.md`. Do not commit `notes/captures/`.
