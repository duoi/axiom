[← Privacy and data](docs/privacy-and-data.md) · [Docs home](README.md)

# Contributing

## Build and run

You need Xcode 27 and macOS 26 or later on Apple silicon.

```bash
xcodebuild build -scheme Axiom -configuration Debug -destination 'platform=macOS' -derivedDataPath build
open build/Build/Products/Debug/Axiom.app
```

Open the built `.app` with `open`; do not launch the binary inside `Contents/MacOS`. Quit the old copy first, so a
stale build is never left running.

## Tests

```bash
xcodebuild test -scheme Axiom -destination 'platform=macOS'
```

The suite is Swift Testing and runs inside the app. Tests that need a store use `EndpointStore.isolated()`, which has its
own preferences, in-memory keys and a temporary history folder, so a test run never touches your real Keychain,
settings or chats.

Behaviour that a test can check is written test-first: add a failing test, run it, then write the code. Streaming,
URL handling, session rules, attachment limits and the cleartext policy must stay covered. Glass, focus and layout are
not snapshot-tested; check those by eye and record a capture (below).

## Signing and the dev endpoint

| File | In git | What |
|---|---|---|
| `Config/Signing.xcconfig` | yes | ad-hoc signing for Debug |
| `Config/Signing.local.xcconfig` | no | your development identity; with it, macOS permissions survive rebuilds |
| `Config/dev-endpoint.example.json` | yes | the shape of the dev endpoint file, with empty strings |
| `Config/dev-endpoint.json` | no | a Debug-only provider: `model`, `completionsURL`, `apiKey` |

A Debug build copies `dev-endpoint.json` into the app and seeds that provider's key into the Keychain. When its URL is
`http`, the build adds an App Transport Security exception for that one host. Never put a key in git, logs or error
text. Release builds are ad-hoc signed by CI.

## Launch options

| Option | Does |
|---|---|
| `--show` | open the card at launch |
| `--settings` | open Settings at launch |
| `--settings-page=<page>` | `general`, `appearance`, `models`, `history` or `about` |
| `--edit-preset=<id>` | open the editor for the provider made from that preset, for example `openai` |
| `--edit-endpoint` | open the editor for the current chat provider (not On-device, which cannot be edited) |
| `--new-ui` | use New UI for this launch without changing the saved setting |
| `--debug` | open the Debug window, for phases, glow, shimmer and the HTTP transcript |
| `--debug-state=<state>` | with `--debug`, put the card in a state, for example `markdown-reply`, `dictate-on`, `missing-key`, `arm-screen` |
| `--demo-prompt=<text>` | Debug builds, with `--show`: type that prompt into the card and send it |

## Captures

`notes/captures/` holds development screenshots and is gitignored; record their paths in `notes/README.md`. Images
for the docs live in `docs/images/` and are committed. To make one:

1. Cover the desktop with a neutral backdrop, so no personal windows end up in the image.
2. Launch with `--debug --debug-state=<state>`, or `--show --demo-prompt=<text>` for a real exchange.
3. Capture the region around the card with `screencapture -R`, or record with `screencapture -v` and convert to GIF.
4. Leave out anything private: hosts, keys, chat history, the Dock.

## Changes and commits

- Update `README.md` or the matching page in `docs/` in the same change when what a person can do changes.
- `notes/README.md` is the running development log.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org): `feat:`, `fix:`, `docs:`,
  `refactor:`, `test:`, `ci:`, `chore:`.
- A push to `main` runs the tests, builds a Release, and publishes it as a GitHub release tagged `build-<commit>`. A
  `v*` tag publishes that version. The test and build steps can only read the repository; a separate job publishes.

[← Privacy and data](docs/privacy-and-data.md) · [Docs home](README.md)
