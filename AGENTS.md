# Axiom

Native macOS menu-bar app. A hotkey shows a Liquid Glass prompt card and streams an OpenAI-compatible chat completion into that card.

## Read first

- `README.md` is the user-facing description. Update it in the same change when behavior, install, or publishing changes. See `.cursor/rules/readme.mdc`.
- `notes/README.md` is the running log.
- `notes/references/launcher-hud.jpg` is the visual spec.
- `notes/plan.md` points at the canonical plan. Do not paste a second copy of that plan into the repo.

## Red, then green

Behavior that can fail a test is written test-first. Add a failing Swift Testing test, run it, then write the code.

Cover SSE parsing, completions URL joining, session rules, attachment limits, and the cleartext URL policy.

Run:

```bash
xcodebuild test -scheme Axiom -destination 'platform=macOS'
```

Glass, focus, and layout are not snapshot tests. After a visual change, capture the live panel and compare it with `notes/references/launcher-hud.jpg`. Record the capture path in `notes/README.md`.

```bash
python3 ~/.codex/skills/screenshot/scripts/take_screenshot.py --app "Axiom" --path notes/captures/<name>.png
```

Screen Recording permission is required once. Use `--list-windows` and `--window-id` for the panel alone. Do not commit `notes/captures/`.

## Secrets

The dev endpoint lives in `Config/dev-endpoint.json`, which is gitignored. `Config/dev-endpoint.example.json` has empty strings. Never put the API key in git, logs, error text, or this file.

The client speaks OpenAI Chat Completions. The model id and host in the dev file are configuration. Any other compatible base URL uses the same client.

## Window

The HUD is a nonactivating panel. Do not call `NSApp.activate` to show it or to type in it. Settings is the exception: opening Settings activates the app. The card stays up.

`.nonactivatingPanel` belongs in the panel initializer.

Center on the screen that contains `NSEvent.mouseLocation`, inside `visibleFrame`. Later height changes pin the top edge.

## Rebuild after app changes

After any change that affects the running app, rebuild the Debug Axiom.app, quit any running Axiom process, open the new .app with `open`, and confirm the process is running before you tell the user the change is ready. Do not leave a stale binary running. Do not launch the Mach-O stub inside Contents/MacOS.

## Out of this version

No tool calls, no markdown renderer. The Agent preset only changes the system prompt.
