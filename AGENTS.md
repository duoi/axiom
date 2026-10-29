# Axiom

Native macOS menu-bar app. A hotkey shows a Liquid Glass prompt card and streams an OpenAI-compatible chat completion into that card.

## Read first

- `README.md` is the user-facing overview. The details live in `docs/` (`using-axiom.md`, `providers.md`, `agent-mode.md`, `privacy-and-data.md`) and `CONTRIBUTING.md`.
- When a change alters what a person can do (the card, hotkey, voice, capture, attachments, history, Settings, providers, keys) or how the app is installed or published, update the matching page in the same change. Leave the docs alone for a comment, rename, or fix that changes none of those facts.
- `notes/` is a local, gitignored working folder: a running log in `notes/README.md`, captures, and visual references. It may not exist in a fresh clone.

## Red, then green

Behavior that can fail a test is written test-first. Add a failing Swift Testing test, run it, then write the code.

Cover SSE parsing, completions URL joining, session rules, attachment limits, and the cleartext URL policy.

Run:

```bash
xcodebuild test -scheme Axiom -destination 'platform=macOS'
```

Glass, focus, and layout are not snapshot tests. After a visual change, capture the live panel and look at it. `CONTRIBUTING.md` (Captures) has the steps; keep personal windows out of anything committed to `docs/images/`.

```bash
mkdir -p notes/captures && screencapture -x -R<x>,<y>,<width>,<height> notes/captures/<name>.png
```

Screen Recording permission is required once.

## Secrets

The dev endpoint lives in `Config/dev-endpoint.json`, which is gitignored. `Config/dev-endpoint.example.json` has empty strings. Never put the API key in git, logs, error text, or this file.

The client speaks OpenAI Chat Completions. The model id and host in the dev file are configuration. Any other compatible base URL uses the same client.

## Window

The HUD is a nonactivating panel. Do not call `NSApp.activate` to show it or to type in it. Settings is the exception: opening Settings activates the app. The card stays up.

`.nonactivatingPanel` belongs in the panel initializer.

Open on the screen that contains `NSEvent.mouseLocation`, centered horizontally and a third of the way down `visibleFrame`. A growing reply pins the top edge and grows down to the floor; only what does not fit lifts the top.

## Rebuild after app changes

After any change that affects the running app, rebuild the Debug Axiom.app, quit any running Axiom process, open the new .app with `open`, and confirm the process is running before you tell the user the change is ready. Do not leave a stale binary running. Do not launch the Mach-O stub inside Contents/MacOS.

## Out of this version

Ask is the default. The Ask/Agent control stays hidden until Settings, Models, Experimental is checked, that provider's Agent box is checked, and that provider is the chat provider. The checkbox defaults off. Agent mode shows the control and turns on tools. Ask does not call tools. On-device Agent does not call tools.
