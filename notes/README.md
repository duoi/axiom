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
