<p align="center">
  <img src="AIHUD/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" alt="Axiom" width="160">
</p>

# Axiom

Axiom is a macOS menu-bar app. A hotkey opens a Liquid Glass prompt card, and the reply streams into that card. It stays out of the Dock.

The app needs macOS 26 or later on Apple silicon. On-device image input needs macOS 27.

## Install

Download `Axiom-macOS.zip` from the [latest GitHub release](https://github.com/duoi/axiom/releases/latest). Unzip it and move `Axiom.app` to Applications.

The published build is ad-hoc signed and not notarized. The first time you open it, right-click the app and choose Open. macOS will remember that choice.

## Open the card

Control-Option-K shows and hides the card. Change that shortcut in Settings. The menu-bar icon also has Show, Settings, Debug, and Quit.

The card is a nonactivating panel. Showing it does not steal focus from the app you were using. Opening Settings does activate Axiom, and the card stays up.

The card centers on the screen under the pointer, inside the visible frame. When a reply grows the card, the top edge stays put.

Escape dismisses the card. A click outside dismisses it unless Settings has "Keep the card up" on, and the reply has already finished. Stopping a stream puts the prompt back in the field.

## The prompt card

Type a prompt and press Return to send. The field is one line by default and stays vertically centered. Settings can turn on a multiline prompt. Then the field wraps, the card grows downward, and the visible field stops at 10 lines. Option-Return or Shift-Return inserts a newline. Return still sends.

While a request is in flight, the field keeps the exact text you sent and cannot be edited. Dictation cannot rewrite it. Success clears the field. Failure puts the text back and unlocks it.

Ask and Agent are presets. Each one appends its own instruction to the endpoint system prompt. Ask asks for a short answer from what you typed or attached. Agent asks for concrete steps and tells the model it cannot run tools, browse, or change the computer. Neither preset calls tools.

The logo menu lists saved providers and models, and a Reasoning submenu. The choice is the same value as Settings.

Screen and Window arm the next send. Screen captures the display. Window captures the front window and needs Accessibility. The capture is not a chip. A highlight tracks the target. The card hides for the shot so it is not in the image.

Add context attaches up to 4 files, 4 MB each. Text files go in as text. Images are sent as JPEG. Anything else is refused.

The mic button dictates into the field. While it is listening, the card shows a waveform. An empty draft shows "Listening...".

When history is on, the shortcut badge swaps for an incognito mark. That mark excludes the current conversation from history. Primary means this chat is not being recorded.

A long reply grows the card, then scrolls. The expand chevron opens the rest of the thread. Waiting with no reply text stays the compact 560 by 108 card. Assistant replies render headings, lists, links, and fenced code. What you type stays plain.

Errors sit on a lip under the card so the toolbar stays inside the glass. A timeout, a missing key, a missing model, a sign-in failure, and a screen-recording denial each keep their own sentence.

## Models

Settings has a table of endpoints. Keys live in the data-protection keychain, one item per endpoint. They are not written into the endpoint list.

A fresh launch shows the on-device row only. Add fills a draft from a preset, or a custom host. Clicking a row selects it. Edit opens the sheet. Make default and Set as vision model are explicit.

Chat and vision can be different endpoints. A send that includes an image uses the vision endpoint. If that endpoint is incomplete, the send stops instead of falling back to the chat model.

On-device chat uses Apple Intelligence through the Foundation Models framework. It needs a Mac that supports Apple Intelligence, with it turned on. Image input on that path needs macOS 27.

These presets are built in:

| Name | Base URL | Auth |
| --- | --- | --- |
| On-device | none | Apple Intelligence |
| OpenAI | `https://api.openai.com/v1` | API key |
| Anthropic | `https://api.anthropic.com/v1` | API key |
| ChatGPT | `https://chatgpt.com/backend-api/codex` | ChatGPT subscription |
| OpenRouter | `https://openrouter.ai/api/v1` | API key |
| Venice | `https://api.venice.ai/api/v1` | API key |
| Moonshot AI | `https://api.moonshot.ai/v1` | API key |
| Z.AI | `https://api.z.ai/api/paas/v4` | API key |
| DeepSeek | `https://api.deepseek.com` | API key |
| Alibaba Cloud Model Studio | `https://dashscope-intl.aliyuncs.com/compatible-mode/v1` | API key |
| SiliconFlow | `https://api.siliconflow.com/v1` | API key |
| Cohere | `https://api.cohere.ai/compatibility/v1` | API key |
| Groq | `https://api.groq.com/openai/v1` | API key |
| xAI | `https://api.x.ai/v1` | API key |
| Together AI | `https://api.together.xyz/v1` | API key |
| Fireworks AI | `https://api.fireworks.ai/inference/v1` | API key |
| Cerebras | `https://api.cerebras.ai/v1` | API key |
| Mistral | `https://api.mistral.ai/v1` | API key |
| Meta Muse | `https://api.meta.ai/v1` | API key |
| LM Studio | `http://127.0.0.1:1234/v1` | none required |
| Ollama | `http://127.0.0.1:11434/v1` | none required |
| Unsloth | `http://127.0.0.1:8888/v1` | API key |

OpenAI-compatible hosts use Chat Completions. Anthropic uses the Messages API. ChatGPT subscription uses the Responses API on the Codex host. Connect in the endpoint editor signs in with ChatGPT and stores the OAuth token in that row's keychain item.

Refresh asks the host for `/models` and keeps the saved model id when it is still in the list. Otherwise it takes the first remaining chat model. The stored URL is not rewritten. A base URL that already ends in `/chat/completions`, `/completions`, or `/messages` is used as the send URL. The models request strips those suffixes so `/v1/models` still works.

Plain `http` is allowed for localhost, `127.0.0.1`, and `::1`. Other cleartext hosts are rejected. An https request will not follow a redirect onto http. A redirect onto a different host is refused, so the key is not sent there.

Reasoning effort is shared by Settings and the logo menu. The default is Medium when nothing is saved. A saved legacy value of `off` loads as None. OpenAI-compatible and ChatGPT send `none`, `minimal`, `low`, `medium`, or `high`. Anthropic omits thinking for None. Otherwise it sends a token budget of 1024, 2048, 8192, or 16384 and raises `max_tokens` above that budget.

The request timeout defaults to 45 seconds. Settings can set 10 to 600. The resource timeout is twice that.

Each endpoint can have its own system prompt. A blank one uses the default prompt from Settings. `%datetime%` becomes the local date and time at send time.

## Voice

Wake on Axiom is off until you turn it on in Settings. The app listens for "Axiom" or "Hey Axiom" at the start of a phrase, then opens the card with the rest of the sentence. Permission is requested from Settings, not from the card.

Pause to send waits about two seconds of silence after a non-empty draft, then sends. Return still sends. Nothing sends while a reply is waiting or streaming.

## Permissions

Microphone and speech recognition are for wake and dictation. Screen Recording is for Screen and Window capture. Window capture also needs Accessibility.

Settings lists each permission. If macOS has not asked yet, the button requests access. If you already denied it, the button opens the matching Privacy pane. Axiom does not edit the TCC database.

## History

History is off by default. When it is on, a finished conversation is stored on this Mac under Application Support `com.stevenjohns.Axiom/History`. Nothing is uploaded.

Settings shows the time and title. Double-click opens the thread. Screenshot saving is a separate switch, off by default. It stores the Screen or Window JPEG with that chat. It does not copy your original files. Delete removes that chat and its stored screenshot.

## Appearance

Glass is the clear card. Matte is the heavier glass. The amount slider adds a veil. At 100% the glass stays clear. Unfocused pills use the same family of glass, not a black fill.

## Debug

The menu-bar Debug item opens a panel for phases, glow, shimmer, and a live HTTP transcript. The transcript redacts authorization headers, API keys, bearer tokens, and secret query parameters. Prompt text stays. You can also launch with `--debug` or `--debug-state=<name>`.

## Build

The Xcode project is `Axiom.xcodeproj`. The scheme is Axiom. GitHub Actions builds it on the `xcode-27` runner, runs the tests, and uploads `Axiom-macOS.zip` to a release. A push to `main` publishes a release tagged with that commit. A `v*` tag publishes that version. The newest of those is the latest release.

Local tests:

```bash
xcodebuild test -scheme Axiom -destination 'platform=macOS'
```

Release signing in the project is ad-hoc. Debug signing on a development Mac uses the Apple Development identity in `project.yml`. The dev endpoint file `Config/dev-endpoint.json` is gitignored. `Config/dev-endpoint.example.json` has empty strings. Do not put an API key in git, logs, or error text.

## License

[MIT](LICENSE). Copyright 2026 Steven Johns.
