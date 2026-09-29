# Model defaults (first slice)

Plan only. Do not implement this pass. `notes/plan.md` stays the pointer to the product plan.

Source: [fastrepl/anarlog](https://github.com/fastrepl/anarlog) `main` (`apps/desktop/src/settings/ai/llm/shared.tsx` and the list/subscription files under `apps/desktop/src/settings/ai/`). Reviewed again on 2026-09-27 after the last note was rejected for leaving this work out.

Anarlog is not a pile of special clients. It keeps a catalog of OpenAI-compatible hosts and one Anthropic-compatible host, each with a default base URL, then lists models from that host when you connect or refresh. The only non-standard path is ChatGPT subscription (Codex OAuth against `https://chatgpt.com/backend-api/codex`, Responses API). This slice builds those defaults, that lookup, and that ChatGPT path in Axiom. It does not leave subscription login or the default rows for a later pass.

HUD already has a table (`chat.endpoints`, `chat.defaultEndpointID`), Keychain `api-key.<uuid>`, a non-removable on-device row, a per-endpoint system prompt, and a global `chat.defaultSystemPrompt`. This slice adds Add-time catalog presets, model listing, an Anthropic send path, and ChatGPT subscription send. Custom Add/Edit stays for hosts that are not in the catalog.

## 1. Default endpoint rows

The table is not pre-filled with catalog hosts. A fresh launch shows On-device only. Catalog hosts appear when the user chooses Add; picking one fills a draft. Save still requires the minimum fields before a row is created. Drop leftover unused previous-seed rows (stock name and URL, empty model and prompt, no key, not vision) without wiping keys. Do not invent hosts. Do not offer entries that have no default URL (Azure OpenAI, Azure AI Foundry, Amazon Bedrock, Google Vertex AI, Cloudflare Workers AI, Custom). Do not offer Anarlog Cloud. Do not offer Gemini (that catalog entry is the native Gemini SDK, not OpenAI or Anthropic). Do not offer Claude / Grok / Copilot / Kimi subscription twins; those are extra OAuth or membership logins. Keep the existing on-device Apple Intelligence row as the first, non-removable local row (Anarlog’s `apple_foundation` equivalent). Clicking a row highlights it only. It does not open the editor, change the default, or change the vision mark. Edit (the button or the context-menu item) opens the editor. Make default and Set as vision model stay explicit buttons.

Anarlog does not ship a pinned model id. After a successful list, keep the saved model if it is still in the list; otherwise take `models[0]`. Until the first successful list, the model field can stay empty or keep whatever the user typed. ChatGPT has no fallback list (`FALLBACK_MODELS.chatgpt` is empty). Anthropic API-key listing uses Anthropic’s own `/models` call, not `/v1/models`.

| Name | Default base URL | Auth | How the model id is chosen |
| --- | --- | --- | --- |
| On-device | (none) | none | Fixed: Apple Intelligence. Not listed from a URL. |
| OpenAI | `https://api.openai.com/v1` | API key | `GET {base}/models`, Bearer key. Keep saved id if still present, else first remaining chat model. |
| Anthropic | `https://api.anthropic.com/v1` | API key | `GET {base}/models`, `x-api-key` plus `anthropic-version: 2023-06-01`. Same keep-or-first rule. |
| ChatGPT | `https://chatgpt.com/backend-api/codex` | ChatGPT subscription | `GET {base}/models?client_version=0.145.0` with the subscription token. No fallback list. Keep saved slug if still present, else first visible slug. |
| OpenRouter | `https://openrouter.ai/api/v1` | API key | OpenAI-style `{base}/models`. |
| Venice | `https://api.venice.ai/api/v1` | API key | OpenAI-style `{base}/models`. |
| Moonshot AI | `https://api.moonshot.ai/v1` | API key | OpenAI-style `{base}/models`. |
| Z.AI | `https://api.z.ai/api/paas/v4` | API key | OpenAI-style `{base}/models`. |
| DeepSeek | `https://api.deepseek.com` | API key | OpenAI-style `{base}/models`. |
| Alibaba Cloud Model Studio | `https://dashscope-intl.aliyuncs.com/compatible-mode/v1` | API key | OpenAI-style `{base}/models`. (Singapore default. Do not invent regional URLs.) |
| SiliconFlow | `https://api.siliconflow.com/v1` | API key | OpenAI-style `{base}/models`. (International default.) |
| Cohere | `https://api.cohere.ai/compatibility/v1` | API key | OpenAI-style `{base}/models`. |
| Groq | `https://api.groq.com/openai/v1` | API key | OpenAI-style `{base}/models`. |
| xAI | `https://api.x.ai/v1` | API key | OpenAI-style `{base}/models`. |
| Together AI | `https://api.together.xyz/v1` | API key | OpenAI-style `{base}/models`. |
| Fireworks AI | `https://api.fireworks.ai/inference/v1` | API key | OpenAI-style `{base}/models`. |
| Cerebras | `https://api.cerebras.ai/v1` | API key | OpenAI-style `{base}/models`. |
| Mistral | `https://api.mistral.ai/v1` | API key | OpenAI-style `{base}/models`. |
| Meta Muse | `https://api.meta.ai/v1` | API key | OpenAI-style `{base}/models`. |
| LM Studio | `http://127.0.0.1:1234/v1` | none required | OpenAI-style `{base}/models` when the local server is up. |
| Ollama | `http://127.0.0.1:11434/v1` | none required | OpenAI-style `{base}/models` when the local server is up. |
| Unsloth | `http://127.0.0.1:8888/v1` | API key (`sk-unsloth-…`) | OpenAI-style `{base}/models`. |

Tag saved rows by a stable preset id so a second launch does not duplicate rows or wipe a user’s URL, key, prompt, or selected model. Existing user-added rows stay. The current Default / bundled-dev row stays if it is not one of these hosts. Make default sets `chat.defaultEndpointID`. A row click does not.

## 2. Model list at connect and refresh

List when the user saves a key or finishes ChatGPT login for that row, and again from an explicit Refresh in the endpoint editor. Do not list on every HUD keystroke.

OpenAI-compatible (Anarlog `listOpenAIModels` / `listGenericModels` in `apps/desktop/src/settings/ai/shared/list-openai.ts`):

- Request: `GET {baseUrl}/models` with `Authorization: Bearer {apiKey}` when a key exists. Join the catalog base URL as Anarlog does (`https://api.openai.com/v1` → `https://api.openai.com/v1/models`). Loopback hosts stay on the existing cleartext policy.
- Response: `{ "data": [ { "id": "…" }, … ] }`. Drop non-chat / old / date-snapshot ids the same way Anarlog does if we share that filter; do not invent a second catalog.
- Store: the last successful id list on the endpoint (UserDefaults, next to `chat.endpoints`), and the selected model string already on `ChatEndpoint.model`.

Anthropic API key (Anarlog `listAnthropicModels` in `list-anthropic.ts`):

- Request: `GET https://api.anthropic.com/v1/models` with `x-api-key: {apiKey}` and `anthropic-version: 2023-06-01`.
- Response: `{ "data": [ { "type", "id", "display_name", "created_at" }, … ], "has_more", … }`. Use `id`.
- Store the same way: list plus selected `model`.

ChatGPT subscription list is in section 3.

On failure: keep the typed or last-selected model id, show an error in Settings (and on send if that model cannot run), and do not delete or rewrite the Keychain secret. An empty list is a failed list, not a reason to clear the key.

The editor shows a picker when the list is non-empty, and still allows typing a model id. Refresh re-runs the same request.

## 3. ChatGPT subscription

This is in the first slice. It is a separate row from OpenAI API key, matching Anarlog’s `chatgpt` vs `openai`.

How Anarlog represents it (`subscriptions/oauth.ts`, `credential.ts`, `fetch.ts`, `models.ts`, `useLLMConnection.ts`):

- Auth: Codex-CLI-compatible OAuth PKCE. Public client id `app_EMoamEEZ73f0CkXaXp7hrann`. Authorize `https://auth.openai.com/oauth/authorize`, token `https://auth.openai.com/oauth/token`, redirect `http://localhost:1455/auth/callback`, scope `openid profile email offline_access`, plus `codex_cli_simplified_flow=true` and `originator=codex_cli_rs`.
- Stored secret: JSON `{ type: "oauth", refresh, access, expires, accountId? }` in the same secret slot they use for API keys. Refresh uses `offline_access`.
- Base URL: `https://chatgpt.com/backend-api/codex`.
- Model list: `GET https://chatgpt.com/backend-api/codex/models?client_version=0.145.0` with `Authorization: Bearer {access}`, `originator: codex_cli_rs`, `OpenAI-Beta: responses=experimental`, `User-Agent: codex_cli_rs`, and `ChatGPT-Account-ID` when known. Body `{ models: [ { slug, visibility? } ] }`. Hide `visibility === "hide"`. No fallback slugs.
- Send: not Chat Completions. Anarlog uses the OpenAI Responses API through that Codex host, with those headers, optional `x-openai-internal-codex-residency` from the JWT, a `session_id`, and body `{ store: false, stream: true }` (they drop `max_output_tokens`). They rewrite `api.openai.com/v1/…` to the Codex host.

What the user does in Settings: Add the ChatGPT preset (or open Edit on a saved ChatGPT row), press Connect, sign in in the browser, return to HUD (localhost callback, or paste the redirect URL if the port is taken). The row shows connected vs not. Refresh lists models. Make default on that row makes the next send use this path.

What we store: the OAuth JSON in Keychain `api-key.<uuid>` for that row only. Access and refresh tokens stay in the Keychain. Persist `accountId` and expiry inside that JSON. Persist the selected model slug on the endpoint. Never put the tokens, the JSON, or the API key in logs, error text, the default-prompt field, or git.

Smallest send that works: refresh the access token if it is expired; `POST https://chatgpt.com/backend-api/codex/responses` with the Codex headers and `ChatGPT-Account-ID`; stream the response into the existing `Session` token path (same card, same Ask/Agent prompt composition). Do not pretend this is `{base}/chat/completions`. If Responses streaming cannot be mapped to the current SSE parser, add a Codex/Responses parser next to `SSEParser` rather than shrinking the slice to API-key-only.

Honest constraints: this reuses the Codex CLI public client and presents as `codex_cli_rs`. It is unofficial, can break when OpenAI changes Codex, and may sit outside OpenAI’s terms for third-party apps. Build it anyway. Do not scrape cookies. Do not log tokens. Fail the send with a short Settings-facing error if login or refresh fails.

## 4. Out of this slice

No tool calls. No Claude / Grok / Copilot / Kimi subscription login. No Gemini native client, no Azure / Bedrock / Vertex / Cloudflare rows, no Anarlog Cloud. No second markdown renderer. Custom hosts stay on Add, not on the seed list.

## 5. Implementation order in this repo

Today: `ChatEndpoint` is `id`, `name`, `completionsURL`, `model`, `systemPrompt`. The catalog lives in `chat.endpoints` / `chat.defaultEndpointID`. Keys are `KeychainStore.chatAccount(for:)` → `api-key.<uuid>`. On-device is `ChatEndpointCatalog.onDeviceID`, always inserted, never deleted. Prompts: per-row `systemPrompt`, else `chat.defaultSystemPrompt`, else the built-in template, then Ask/Agent append. Cloud send is `ChatClient` → OpenAI Chat Completions. On-device send is `OnDeviceChat`. Settings Chat is the table plus the default-prompt editor.

1. Types and Add-time presets. Add a stable `preset` (or `kind` + `auth`) on `ChatEndpoint`: `onDevice`, `openaiCompatible`, `anthropic`, `chatgptSubscription`, plus optional `presetID` matching Anarlog’s ids. The table stays quiet: On-device plus user-saved or migrated rows. Catalog hosts fill a draft from Add; they are not inserted on launch. Prune unused previous-seed rows without wiping keys. Do not write empty keys over existing Keychain accounts. Tests: table has no unselected presets; choosing a preset fills a draft; Save creates one row; unpicked presets stay absent; on-device cannot be removed; existing default id still resolves; a row click does not present the editor and Edit does.

2. Model list. New list helper (test-first): OpenAI-style `{base}/models`, Anthropic `{base}/models` with `x-api-key`, ChatGPT Codex `/models`. Persist the last list beside the catalog. Endpoint editor: picker + Refresh. Failure keeps the model string and the key. Wire list on save-key / after ChatGPT connect.

3. Settings. `SettingsView` Chat table shows On-device and saved rows. Add offers the catalog plus Custom. Click highlights only. Edit opens the editor. Make default and Set as vision model are explicit. Editor: API-key field for key rows; Connect / Disconnect for ChatGPT; no URL or key field on on-device; no URL field on ChatGPT (URL is fixed); URL stays editable on custom and on saved OpenAI-compatible rows so a user can point at a proxy. Editing a prompt or the global default still must not clear URLs, models, or secrets.

4. Anthropic send. When the default row is Anthropic, stream Messages (`x-api-key`, `anthropic-version`) into `HUDModel` the same way Completions tokens do. Completions stay the path for OpenAI-compatible rows.

5. ChatGPT send. Local callback on port 1455, PKCE, Keychain JSON, refresh, Responses stream. `ChatRouting` / `EndpointStore.route` treat a selected ChatGPT row as that path, not Completions and not on-device. Selecting a cloud API-key row must not use ChatGPT or on-device.

6. Verify. Red/green around the quiet table, Add-time drafts, click-does-not-open-editor, list failure, ChatGPT row selection, and “do not wipe the key.” `xcodebuild test -scheme Axiom -destination 'platform=macOS'`. Launch Settings Chat and capture the quiet table after a row click (no detail sheet), the Add defaults chooser, the model picker, and Connect on a ChatGPT draft. Do not commit captures or `Config/dev-endpoint.json`. Do not log secrets.
