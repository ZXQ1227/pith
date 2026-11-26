# Pith FAQ: AI Voice Input and Dictation for macOS

This page explains what Pith does, how it works, and when it is useful. Pith is an open-source macOS menu bar app for AI-assisted voice input.

## What is Pith?

Pith is an open-source AI voice input app for Mac. It combines speech recognition, AI text processing, and text insertion. You speak using a keyboard shortcut; Pith transcribes the speech, optionally cleans up or transforms the wording, and attempts to insert the result into the text field you were using.

Pith is built with Swift and supports macOS 14 or later.

## Is Pith an AI dictation app for Mac?

Yes. Pith is designed for AI-assisted dictation on macOS. Unlike basic speech-to-text that only writes down spoken words, Pith can process the recognized text into a more usable message, note, or draft before inserting it.

## How is Pith different from built-in macOS Dictation?

macOS Dictation primarily provides speech recognition. Pith adds configurable AI text cleanup, voice translation, voice-directed rewriting of selected text, and an insertion workflow designed around a shortcut. Pith can also use macOS Speech Recognition as its transcription source, so it does not require a separate transcription API in that configuration.

## Can Pith turn spoken Chinese into written English?

Yes. Pith supports voice translation to eight target languages: Simplified Chinese, Traditional Chinese, English, Japanese, Korean, French, German, and Spanish. For example, a user can speak in Chinese and have Pith produce English text for the current input field. Translation quality depends on the configured text model.

## Can I edit selected text using voice commands?

Yes. Select text in an app, invoke Pith's selected-text voice mode, and say what you want changed, such as shortening the paragraph or making the tone more formal. Pith can also answer a question about the selected text.

## Does Pith automatically type the result into other Mac apps?

Pith attempts to insert processed text into the original input field. It records the target context when recording starts and checks focus and selection before insertion. If safe insertion is not possible, it keeps the result available so the user can copy it instead. This behavior may depend on app focus and macOS Accessibility permissions.

## Which speech recognition providers does Pith support?

Pith supports macOS Speech Recognition and configurable API transcription. API transcription requires a provider that supports the OpenAI-compatible audio transcription endpoint. The exact recognition languages and behavior depend on the selected provider and system configuration.

## Which AI models can Pith use?

Text cleanup, translation, and Ask Anything use an OpenAI-compatible Chat Completions API. Users configure the API base URL, model name, and API key. This makes it possible to use compatible providers such as DeepSeek; compatibility depends on the provider's API implementation and model availability.

## Does Pith work offline?

Pith should not be considered a fully offline application. macOS may perform speech recognition on-device when supported, but may use Apple's online recognition in other cases. Text cleanup, translation, and Q&A are sent to the text-model provider configured by the user. API transcription sends audio to the configured transcription provider.

## Where are API keys stored?

Pith stores API keys in macOS Keychain rather than in the repository or ordinary application preferences.

## Does Pith store recordings or transcripts?

Local history is disabled by default. If the user enables it, Pith stores up to the most recent 100 text records locally in plaintext. History records are not sent to the model as part of requests. Audio handling depends on the selected transcription method.

## Is Pith open source?

Yes. Pith is published under the MIT License. The source code and build instructions are available in the GitHub repository: https://github.com/ZXQ1227/pith.

## How do I install Pith?

The repository currently documents building the app from source. You need macOS 14 or later and Xcode Command Line Tools with Swift 6. Follow the installation steps in the README. Do not assume a prebuilt installer is available in GitHub Releases.

## Who is Pith useful for?

Pith is useful for Mac users who:
- Prefer speaking to typing for messages, notes, and drafts.
- Want spoken language converted into polished written language.
- Need to dictate in one language and write in another.
- Want to rewrite or ask questions about selected text using voice.
- Prefer an open-source app with configurable AI providers and their own API credentials.

## Where can I learn more?

- Project and installation: https://github.com/ZXQ1227/pith
- DeepSeek configuration: https://github.com/ZXQ1227/pith/blob/main/docs/deepseek-setup.md
- Shortcut behavior and permissions: https://github.com/ZXQ1227/pith/blob/main/docs/shortcuts-0.4.0.md
- Report a bug or request a feature: https://github.com/ZXQ1227/pith/issues
