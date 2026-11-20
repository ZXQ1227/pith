# Pith

Pith is a macOS menu bar voice-input app prototype. It records a short audio clip, transcribes with macOS system speech recognition or an OpenAI-compatible transcription endpoint, refines the text with a chat-completions endpoint, and lets you copy or paste the result back into the application that was focused when recording began.

## Requirements

- macOS 14 or later
- Xcode command line tools with Swift 6
- An OpenAI-compatible `POST /chat/completions` API; `POST /audio/transcriptions` is needed only for API transcription. macOS speech recognition needs Speech permission and may need a network connection.

## Build and test

```sh
swift test --scratch-path .build --cache-path .cache --manifest-cache local
bash build-app.sh /private/tmp/pith-release/Pith.app
open /private/tmp/pith-release/Pith.app
```

The app is ad-hoc signed for local use. For distribution, sign and notarize it with your Apple Developer identity.

An optional absolute `.app` output path keeps signing outside synced folders. Without it, the script uses `dist/Pith.app`. If the output folder is managed by a cloud file provider (for example iCloud Documents), reattached Finder metadata can make codesign reject the bundle; in that case use a temporary output path such as `/private/tmp`. The script only strips signing-incompatible Finder/resource-fork attributes from the generated bundle; it does not modify source metadata or system settings.

## Configure

Open Pith's menu bar item, choose **设置...**, and set the transcription source, API base URL, text model, and API key. The API key is stored in macOS Keychain. With API transcription, the app sends the current audio, transcription, mode-specific instruction, and personal dictionary to your configured provider. With system transcription, macOS processes the audio (preferably on-device, with Apple server processing possible otherwise), and only recognized text and vocabulary go to the configured model. Dictation and translation do not read field contents. Ask Anything reads only the explicitly selected text through macOS Accessibility when triggered, and sends that selection with your spoken instruction to the configured model. It never reads whole windows, pages, or clipboard contents for context. API transcription providers must support the optional `prompt` field to use dictionary hints at the recognition stage. For DeepSeek V4, see [setup instructions](docs/deepseek-setup.md).

Press **Fn / Globe** once to start dictation and again to finish. Press **Fn + Left Shift** to start translation, or **Fn + Space** to ask a question or edit selected text, then **Fn** to finish. A gesture is recognized on Fn release, so you do not need to keep holding it; other Fn chords do not start dictation. Fn + Space consumes Space down/repeat/up events so it does not type a space into your document. **Esc** cancels an active session. Hold bare Fn for 600 ms while idle to reveal the shortcut guide; releasing dismisses and destroys the guide without starting a recording. You can add Left Shift or Space while the guide is visible to choose that mode. The compact, nonactivating recording capsule emphasizes a live white waveform with cancel/finish controls. After finishing, the same panel becomes a Thinking capsule during recognition, model processing and insertion. Right-click the translation capsule to change its target language, or choose it in settings. It cannot take keyboard focus. After successful automatic input, it disappears without opening a result window or editor.

Fn needs **Accessibility** permission. The first upgrade to this shortcut profile preserves your previous combination (normally **Control-Option-Space**) as a dictation backup and adds **Control-Option-Shift-Space** for translation. These combinations remain available without Accessibility permission. In **设置… → 快捷键**, add up to eight extra combinations with separate dictation/translation/Ask intent for external keyboards, or switch the primary shortcut back to a combination. Combination shortcuts support toggle or hold-to-talk; Fn always uses toggle. Shortcut capture temporarily suspends Pith global shortcuts so recording a binding cannot start dictation.

Pith captures the foreground app and accessible text-input identity when recording starts. Ordinary input reads no field contents. On success it automatically pastes only into that same focused editable field. Known selection ranges must match; when an app exposes no range at either capture or completion, ordinary dictation/translation may paste at the current caret in that same field. A changed or partly unavailable range blocks automatic paste. Ask replacements require both an unchanged known range and the original selected text. A failed paste retains a compact recovery notice, not an automatically opened editor. When there is no editable target, the result is available in a nonactivating card. macOS Accessibility permission is needed to verify the input location and send the paste command. If the system refuses that action, Pith retains the text and reports the reason.

If a combination is already occupied, Pith disables that binding and reports the conflict in settings. It does not silently observe an occupied shortcut. Fn monitoring inspects modifier edges and pressed state solely to reject other chords; it does not read or retain typed characters. Sleep, session changes, permission loss, and event-tap interruptions reset pending gestures.

## Current scope

- Fn dictation, Fn + Left Shift translation, Fn + Space Ask Anything, configurable extra shortcuts, optional hold-to-talk for combinations, and menu bar controls for preview, copy, and safe paste.
- Ask Anything answers questions in a compact card, rewrites explicitly selected editable text in place, and inserts requested drafts into an empty selection. Asking about a selection leaves it unchanged. Answer cards dismiss with Escape, the close button, or an outside click. Ask uses a separate model request contract from dictation so questions in ordinary dictation remain questions.
- AAC/M4A capture and OpenAI-compatible two-stage processing.
- Keychain API key storage and local provider preferences.
- Translation into Simplified Chinese, Traditional Chinese, English, Japanese, Korean, French, German, or Spanish. Choose the target in the menu or settings; actual translation quality depends on the configured model.
- Five expression styles: natural, concise, formal, casual, and bullet points. The menu/settings choice applies to future recordings; the editor can change the current text independently.
- Dictation and refinement preserve spoken questions and requests as text. Saying “请帮我写一封邮件” should produce that request, not generate the email. Translation translates the request itself. Model instructions separate the transcript from the editing task and retain corrections, conditions, and negations; fidelity still depends on the configured model.
- A result editor with manual corrections, original transcript inspection/copy, one-version recovery, and text-only refinement or translation from either current text or the original transcript. Reprocessing never automatically pastes.
- Personal dictionary with add, search, remove, case-insensitive duplicate checks, and a 100-word limit (80 characters per word). Terms guide recognition and refinement rather than performing blind text replacement.
- Opt-in local text history: search original/refined text, copy, delete a record, or confirm clearing all records. Retains the latest 100 entries; retries update the same entry.
- Recognition checkpoints preserve the raw text immediately. Refinement failures and cancellations keep existing text; retries skip recognition once text is available. Unrefined results are clearly labeled. Retried results require explicit copy/insertion.
- Actionable API error messages for authentication, missing endpoints/models, rate limits, and service failures; provider error bodies are never displayed because they may echo keys or submitted text.
- No cloud sync, automatic vocabulary learning, per-app tone adaptation, whole-screen context, or Opus encoding yet. Ask currently uses the configured text model without web retrieval or website actions; it cannot verify live information. Selected-text context is limited to 12,000 characters and depends on the source app exposing its selection through Accessibility. Sensitive/blocked application contexts are not read.

## Dictionary and history

Choose **词典与历史** in the menu bar panel. History is **off by default**. Enabling it stores only subsequent completed transcriptions (including clearly labeled partial results). Disabling it stops new saves but preserves existing records until you delete them. History is never included in API prompts. The dictionary is sent to the configured API for each recording, even when history is off.

Data is stored in `~/Library/Application Support/app.pith.desktop/library.json` using atomic writes and owner-only file permissions. This is local plaintext, not encrypted storage; OS backups may include it. A corrupt or unreadable library is left untouched and library writes are disabled until the file is repaired and the app restarted. API keys remain only in Keychain. Audio is deleted as soon as recognition succeeds; failed-recognition audio is kept only until cancellation, a new recording, or normal shutdown.

## Edit and reuse a result

After dictation, click **编辑文字** on the floating bar or **编辑、换风格或再次翻译…** in the menu panel. Edit the text and choose **保存修改**, **保存并复制**, or **保存并插入**. Unsaved edits survive closing the editor and block a new recording until saved or discarded. Starting a new recording or quitting clears the in-memory draft; enabling history is the way to retain saved text between sessions.

Choose a processing mode, expression style, and **当前文字** or **原始转写**, then click **重新整理** or **生成译文**. Changes are committed before the request; failure preserves that version, and **恢复上一版** restores the last successful text/version settings. Only the selected text and dictionary are sent to the provider. Successful operations update the same history entry when history is enabled; previous versions remain in memory only.

## Version and verification

The current source version is **0.5.1 (10)**. See [0.5.1 verification](docs/verification-0.5.1.md) for the latest installation verification notes and backup paths. Build output alone does not update installed copies. After an upgrade, quit older Pith instances and verify the running executable path and version: `open` may activate an existing older instance with the same bundle ID. Local ad-hoc signing can cause macOS to request microphone and speech recognition permission again after an upgrade; allow them when starting the next recording.

Tests use a local `URLProtocol` stub and temporary files; they do not contact an API, access your real dictionary/history, or record audio. They cover request contents, translation/style selection, text checkpoints, editing/recovery, partial failures, cancellation, dictionary validation, opt-in history, retry deduplication, persistence, and old/corrupt-file handling, alongside the existing interaction tests. Live speech quality and cross-app insertion require microphone/Accessibility permissions and a configured provider. See [0.3.0 scope](docs/value-features-0.3.0.md) and [0.4.0 shortcut behavior](docs/shortcuts-0.4.0.md).
