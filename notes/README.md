# Notes

## 2026-09-27

- Scaffolded the repo. The visual spec is `notes/references/launcher-hud.jpg`.
- The dev endpoint is gitignored at `Config/dev-endpoint.json`. The committed example file has empty strings.
- Wake word is later. This version has no SpeechAnalyzer, listening mark, or microphone toggle.
- The client is OpenAI Chat Completions. The dev file only supplies the model id, URL, and key.
- `AIHUD.app/Contents/MacOS/AIHUD --show` opens the card without the hotkey, for a visual check.
- The idle card is 560 by 108. A reply grows it downward and the top stays put. Captures: `notes/captures/hud-reply-desktop-d1.png` and `notes/captures/hud-reply.png`.
- Checked on this Mac: glass shows the window behind it, Cursor keeps the menu bar, Control-Option-K toggles once, a follow-up includes the earlier turn, a click outside leaves a finished reply up and dismisses a stream, and dismissing a stream puts that prompt back in the field.
- The API key is in the data protection keychain. An ad-hoc rebuild would otherwise ask for the login keychain password on every launch.
- Clicking the glass no longer distorts the card. Ask and Agent are a plain menu again, with no subtitle. Screen and Window arm the next send from a chevron; the choice sticks, and the capture is not a chip. Settings has General, Chat, and Vision, and Vision is its own URL, model, and key. Keep the card up is on by default. The Agent and Screen controls keep a fixed width. Screen sits second, and its chevron is inside the selection pill. Capture: `notes/captures/hud-toolbar-armed.png`.
- Command-A, cut, copy, paste, undo, and redo reach the prompt while the card is up. An Edit menu covers the same commands in Settings.
- Settings is a fixed sidebar, not a collapsing split view. General, Appearance, Chat, Vision, and About. Appearance Glass is clear glass. Matte is regular glass. The amount slider is a veil. Ask is a toggle that keeps Agent's width. Unfocused pills use regular glass, not a black fill. About links to github.com/duoi/axiom. Spacing, corner radius, and row height live in `HUDMetrics`. The Agent pill and an armed Screen control use the same glass as the card, and go matte when the card is not key, Reduce Transparency is on, or Settings asks for matte. Highlighted pills use `HUDMetrics.pillInset` (8) on every side and hug their content. Opening Settings leaves the card up. Captures: `notes/captures/hud-toolbar.png`, `notes/captures/hud-toolbar-desktop-d1-d1.png`, `notes/captures/settings-general.png`, `notes/captures/settings-appearance.png`, `notes/captures/settings-about.png`, `notes/captures/hud-with-settings-d1.png`, `notes/captures/hud-pills-armed.png`, `notes/captures/hud-pills-unfocused.png`, `notes/captures/hud-pills-unfocused-desktop-d1.png`.
