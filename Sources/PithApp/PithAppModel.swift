import AppKit
import ApplicationServices
import AVFoundation
import OSLog
import Speech
import PithCore
import SwiftUI

@MainActor
@Observable
final class PithAppModel {
    private var session = SessionState()
    var phase: SessionPhase { session.phase }
    private(set) var draft: TextDraft?
    var editorText = ""
    var hasUncommittedEdits: Bool { draft != nil && editorText != draft?.text }
    var result: ProviderResult? { draft?.result }
    private(set) var statusMessage = "点击开始，或按快捷键说话"
    private(set) var settingsMessage = ""
    private(set) var apiKeyIsConfigured = false
    private(set) var microphoneAuthorized = false
    private(set) var speechAuthorized = false
    private(set) var accessibilityAuthorized = false
    private(set) var shortcutError: String?
    private(set) var shortcutSettingsMessage = ""
    private(set) var additionalShortcuts: [ShortcutBinding]
    private(set) var recordingUsesHold = false
    private(set) var recordingTriggerTitle = "Fn"
    var sessionMode: DictationMode { recordedMode }
    private(set) var completionDisposition = CompletionDisposition.copyNeeded
    private var presentationDismissed = false
    var presentation: SessionPresentation {
        presentationDismissed ? .hidden
            : .resolve(phase: phase, completion: completionDisposition, hasInputTarget: capturedTarget != nil)
    }
    var recordingTargetLanguage: OutputLanguage {
        get { recordedOptions.targetLanguage }
        set {
            guard phase == .recording, recordedMode == .translate else { return }
            recordedOptions.targetLanguage = newValue
            targetLanguage = newValue
        }
    }
    private(set) var recordingDuration: TimeInterval = 0
    private(set) var inputLevel: Double = 0
    private(set) var isInserting = false
    private var pendingInput: ProcessingInput?
    var canRetry: Bool { pendingInput != nil && !phase.isActive && !isInserting }
    var retryTitle: String { pendingInput?.isText == true ? "重试文字整理" : "重试语音识别" }
    private(set) var library = PersonalLibrary()
    private(set) var libraryMessage = ""
    private(set) var libraryAvailable = true
    var mode: DictationMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "dictationMode") }
    }
    var targetLanguage: OutputLanguage {
        didSet { UserDefaults.standard.set(targetLanguage.rawValue, forKey: "translationLanguage") }
    }
    var outputStyle: OutputStyle {
        didSet { UserDefaults.standard.set(outputStyle.rawValue, forKey: "outputStyle") }
    }
    private(set) var configuration: ProviderConfiguration
    var onSessionChange: (@MainActor () -> Void)?
    var onRecordingWillStart: (@MainActor () -> Void)?
    var onDraftNeedsAttention: (@MainActor () -> Void)?
    var onShortcutHintChange: (@MainActor (Bool) -> Void)?

    var shortcut: DictationShortcut {
        didSet {
            UserDefaults.standard.set(shortcut.rawValue, forKey: "dictationShortcut")
            interaction.reset()
            installGlobalShortcuts()
        }
    }
    var activationMode: ShortcutActivationMode {
        didSet {
            UserDefaults.standard.set(activationMode.rawValue, forKey: "shortcutActivationMode")
            interaction = ShortcutInteraction(mode: activationMode)
        }
    }
    var automaticallyInsert: Bool {
        didSet { UserDefaults.standard.set(automaticallyInsert, forKey: "automaticallyInsert") }
    }
    var interactionSounds: Bool {
        didSet { UserDefaults.standard.set(interactionSounds, forKey: "interactionSounds") }
    }

    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let keychain = APIKeyStore()
    @ObservationIgnored private let logger = Logger(subsystem: "app.pith.desktop", category: "session")
    @ObservationIgnored private var hotkey: HotkeyController?
    @ObservationIgnored private var interaction = ShortcutInteraction(mode: .toggle)
    @ObservationIgnored private var capturedTarget: InsertionTarget?
    @ObservationIgnored private var preparedTarget: InsertionTarget?
    @ObservationIgnored private var lastActiveApplication: NSRunningApplication?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var insertionTask: Task<Void, Never>?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var audioURL: URL?
    private var recordedMode: DictationMode = .dictate
    private var recordedOptions = ProcessingOptions()
    private var recordedAskContext = AskContext()
    @ObservationIgnored private var recordedSpeechSource: TranscriptionSource = .api
    @ObservationIgnored private var recordedSpeechLocale = "zh-CN"
    @ObservationIgnored private var recordedHistoryID = UUID()
    @ObservationIgnored private var recordedAt = Date()
    @ObservationIgnored private var shouldInsertAfterProcessing = false
    @ObservationIgnored private let libraryStore: LocalLibraryStore

    init() {
        let defaults = UserDefaults.standard
        let savedMode = DictationMode(rawValue: defaults.string(forKey: "dictationMode") ?? "") ?? .dictate
        mode = savedMode == .rewrite ? .dictate : savedMode
        targetLanguage = OutputLanguage(rawValue: defaults.string(forKey: "translationLanguage") ?? "") ?? .simplifiedChinese
        outputStyle = OutputStyle(rawValue: defaults.string(forKey: "outputStyle") ?? "") ?? .natural
        libraryStore = LocalLibraryStore(fileURL: URL.applicationSupportDirectory
            .appendingPathComponent("app.pith.desktop", isDirectory: true)
            .appendingPathComponent("library.json"))
        configuration = defaults.decode(ProviderConfiguration.self, forKey: "providerConfiguration")
            ?? ProviderConfiguration()
        automaticallyInsert = defaults.object(forKey: "automaticallyInsert") as? Bool ?? true
        interactionSounds = defaults.object(forKey: "interactionSounds") as? Bool ?? true
        let oldShortcut = DictationShortcut(rawValue: defaults.string(forKey: "dictationShortcut") ?? "") ?? .controlOptionSpace
        if defaults.integer(forKey: "shortcutProfileVersion") < 1 {
            // Retain the working legacy combination while enabling the requested Fn profile.
            shortcut = .function
            activationMode = .toggle
            additionalShortcuts = [ShortcutBinding.preset(oldShortcut) ?? ShortcutBinding.preset(.controlOptionSpace)!,
                                   .translationFallback]
            defaults.set(shortcut.rawValue, forKey: "dictationShortcut")
            defaults.set(activationMode.rawValue, forKey: "shortcutActivationMode")
            defaults.encode(additionalShortcuts, forKey: "additionalShortcuts")
            defaults.set(1, forKey: "shortcutProfileVersion")
        } else {
            shortcut = oldShortcut
            activationMode = ShortcutActivationMode(rawValue: defaults.string(forKey: "shortcutActivationMode") ?? "") ?? .toggle
            additionalShortcuts = defaults.decode([ShortcutBinding].self, forKey: "additionalShortcuts") ?? []
        }
        interaction = ShortcutInteraction(mode: activationMode)
        do { library = try libraryStore.load() }
        catch {
            libraryAvailable = false
            libraryMessage = "本地词典和历史读取失败，原文件未改动。请检查文件权限或恢复 library.json 后重新启动。"
        }
        refreshReadiness()
        rememberFrontmostApplication()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rememberFrontmostApplication() }
        })
        hotkey = HotkeyController(
            onPress: { [weak self] trigger, intent, isFunction in
                self?.shortcutPressed(trigger: trigger, intent: intent, isFunction: isFunction)
            },
            onRelease: { [weak self] trigger in self?.shortcutReleased(trigger: trigger) },
            onCancel: { [weak self] in self?.cancel() },
            onReset: { [weak self] in self?.interaction.reset() },
            onStatusChange: { [weak self] message in self?.shortcutError = message },
            onHintChange: { [weak self] visible in self?.onShortcutHintChange?(visible) },
            canShowHint: { [weak self] in self.map { !$0.phase.isActive && !$0.isInserting } ?? false }
        )
    }

    func installGlobalShortcuts() { hotkey?.configure(shortcut, additional: additionalShortcuts) }

    func setShortcutCaptureActive(_ active: Bool) {
        guard !phase.isActive else { return }
        interaction.reset()
        hotkey?.setSuspended(active)
    }

    @discardableResult
    func addShortcut(_ binding: ShortcutBinding) -> Bool {
        do {
            try binding.validate()
            guard additionalShortcuts.count < 8 else {
                throw PithError.invalidConfiguration("最多添加 8 个额外快捷键，请先移除不再使用的组合。")
            }
            guard !additionalShortcuts.contains(where: { $0.matches(binding) }),
                  ShortcutBinding.preset(shortcut)?.matches(binding) != true else {
                throw PithError.invalidConfiguration("这个组合已被 Pith 使用，请选择另一个。")
            }
            additionalShortcuts.append(binding)
            saveShortcutBindings()
            shortcutSettingsMessage = "已添加 \(binding.title) · \(binding.intent.title)"
            return true
        } catch { shortcutSettingsMessage = error.localizedDescription; return false }
    }

    func removeShortcut(_ id: UUID) {
        additionalShortcuts.removeAll { $0.id == id }
        saveShortcutBindings()
        shortcutSettingsMessage = "已移除快捷键"
    }

    private func saveShortcutBindings() {
        UserDefaults.standard.encode(additionalShortcuts, forKey: "additionalShortcuts")
        interaction.reset()
        installGlobalShortcuts()
    }

    @discardableResult
    func addDictionaryWord(_ word: String) -> Bool {
        updateLibrary(success: "已加入词典，下次录音生效") { try $0.dictionary.add(word) }
    }

    func removeDictionaryWord(_ word: String) {
        updateLibrary(success: "已移除词语") { $0.dictionary.remove(word) }
    }

    func setHistoryEnabled(_ enabled: Bool) {
        updateLibrary(success: enabled ? "已开启本地历史" : "已停止保存，已有记录仍可查看或清空") {
            $0.historyEnabled = enabled
        }
    }

    func removeHistory(_ id: UUID) {
        updateLibrary(success: "已删除这条记录") { $0.removeHistory(id: id) }
    }

    func clearHistory() {
        updateLibrary(success: "本地历史已清空") { $0.clearHistory() }
    }

    func copyHistory(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        libraryMessage = NSPasteboard.general.setString(entry.text, forType: .string)
            ? "已复制历史文字" : "复制失败，请选择文字手动复制"
    }

    @discardableResult
    private func updateLibrary(success: String?, _ update: (inout PersonalLibrary) throws -> Void) -> Bool {
        guard libraryAvailable else { return false }
        do {
            var updated = library
            try update(&updated)
            try libraryStore.save(updated)
            library = updated
            if let success { libraryMessage = success }
            return true
        } catch let error as PithError {
            libraryMessage = error.localizedDescription
        } catch {
            libraryMessage = "本地保存失败，改动尚未保存。请检查磁盘空间和 Pith 数据文件夹权限。"
        }
        return false
    }

    private func saveHistory(_ output: ProviderResult) {
        guard library.historyEnabled, let settings = draft?.settings else { return }
        let entry = HistoryEntry(id: recordedHistoryID, createdAt: recordedAt, mode: settings.mode,
                                 targetLanguage: settings.language, outputStyle: settings.style, result: output)
        updateLibrary(success: nil) { $0.record(entry) }
    }

    var shortcutHint: String {
        if phase == .recording {
            if shortcut == .function, !accessibilityAuthorized, !recordingUsesHold {
                return "点击结束，或使用备用组合键 · Esc 取消"
            }
            return recordingUsesHold
                ? "松开 \(recordingTriggerTitle) 结束 · Esc 取消"
                : "再按 \(shortcut.title) 结束 · Esc 取消"
        }
        if shortcut == .function { return "Fn 口述 · Fn + 左 Shift 翻译 · Fn + Space 问任何问题" }
        return activationMode == .toggle
            ? "按 \(shortcut.title) 开始，再按一次结束"
            : "按住 \(shortcut.title) 说话，松开结束"
    }

    func refreshReadiness() {
        apiKeyIsConfigured = !(keychain.read()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
        accessibilityAuthorized = AXIsProcessTrusted()
        hotkey?.refreshFunctionKeyAccess()
    }

    /// Capture before opening Pith's popover changes the foreground application.
    func prepareForPopover() {
        rememberFrontmostApplication()
        preparedTarget = PasteboardInserter.captureTarget(lastActiveApplication)
    }

    func saveSettings(baseURL: String, transcriptionModel: String, textModel: String, apiKey: String,
                      transcriptionSource: TranscriptionSource, speechLocale: String) {
        let updated = ProviderConfiguration(
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            transcriptionModel: transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines),
            textModel: textModel.trimmingCharacters(in: .whitespacesAndNewlines),
            transcriptionSource: transcriptionSource, speechLocale: speechLocale
        )
        do {
            _ = try updated.validatedBaseURL()
            guard (updated.transcriptionSource == .system || !updated.transcriptionModel.isEmpty), !updated.textModel.isEmpty else {
                throw PithError.invalidConfiguration("转写模型和文本模型都不能为空。")
            }
            let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanKey.isEmpty { try keychain.save(cleanKey) }
            configuration = updated
            UserDefaults.standard.encode(updated, forKey: "providerConfiguration")
            refreshReadiness()
            settingsMessage = "设置已保存"
        } catch {
            settingsMessage = error.localizedDescription
        }
    }

    func clearAPIKey() {
        do {
            try keychain.delete()
            refreshReadiness()
            settingsMessage = "API Key 已从 Keychain 删除"
        } catch { settingsMessage = error.localizedDescription }
    }

    func openPermissionSettings(microphone: Bool) {
        let pane = microphone ? "Privacy_Microphone" : "Privacy_Accessibility"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    func requestMicrophonePermission() {
        Task { @MainActor in
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                refreshReadiness()
            } else { openPermissionSettings(microphone: true) }
        }
    }

    func requestSpeechPermission() {
        Task {
            do {
                if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                    try await SystemTranscriber.authorize()
                } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
                    NSWorkspace.shared.open(url)
                }
            } catch { settingsMessage = error.localizedDescription }
            refreshReadiness()
        }
    }

    func startRecording(modeOverride: DictationMode? = nil, triggerTitle: String? = nil, usesHold: Bool = false) {
        guard !hasUncommittedEdits else {
            statusMessage = "编辑器有未保存的修改，请先保存修改或放弃修改，再开始录音。"
            interaction.reset()
            onDraftNeedsAttention?()
            return
        }
        guard !isInserting, let id = session.begin() else { return }
        discardAudio()
        pendingInput = nil
        draft = nil
        editorText = ""
        recordingDuration = 0
        inputLevel = 0
        recordedMode = modeOverride ?? mode
        completionDisposition = .copyNeeded
        presentationDismissed = false
        recordedAskContext = AskContext()
        recordingUsesHold = usesHold
        recordingTriggerTitle = triggerTitle ?? shortcut.title
        recordedOptions = ProcessingOptions(targetLanguage: targetLanguage, dictionary: library.dictionary, style: outputStyle)
        shouldInsertAfterProcessing = automaticallyInsert
        recordedSpeechSource = configuration.transcriptionSource
        recordedSpeechLocale = configuration.speechLocale
        recordedHistoryID = id
        recordedAt = Date()
        rememberFrontmostApplication()
        let frontmost = NSWorkspace.shared.frontmostApplication
        capturedTarget = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            ? preparedTarget : PasteboardInserter.captureTarget(frontmost)
        if recordedMode == .ask {
            do {
                let app = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
                    ? lastActiveApplication : frontmost
                let capture = try PasteboardInserter.captureAsk(app)
                capturedTarget = capture.target
                recordedAskContext = capture.context
            } catch { fail(error.localizedDescription, id: id); return }
        }
        preparedTarget = nil
        guard let key = keychain.read(), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail(PithError.missingAPIKey.localizedDescription, id: id)
            return
        }
        do { _ = try configuration.validatedBaseURL() }
        catch { fail(error.localizedDescription, id: id); return }
        statusMessage = "正在准备麦克风…"
        onRecordingWillStart?()
        if frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            lastActiveApplication?.activate(options: [])
        }
        notifySessionChange()
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                if recordedSpeechSource == .system { try await SystemTranscriber.authorize() }
                try await recorder.start()
                try Task.checkCancellation()
                guard session.transition(to: .recording, for: id) else { return }
                refreshReadiness()
                switch recordedMode {
                case .translate: statusMessage = "正在听，完成后翻译成所选语言"
                case .ask: statusMessage = recordedAskContext.selectedText == nil
                    ? "说出问题或写作要求，再按 Fn 完成" : "已读取选中文字，说出修改要求或问题"
                default: statusMessage = "正在听，请自然说话"
                }
                if interactionSounds { NSSound(named: "Tink")?.play() }
                startMetering(id: id)
                notifySessionChange()
            } catch is CancellationError {
                // cancel() already invalidates this session before a new one can begin.
            } catch {
                guard session.isCurrent(id) else { return }
                fail(error.localizedDescription, id: id)
            }
        }
    }

    func stopRecordingAndProcess() {
        guard phase == .recording, let id = session.sessionID else { return }
        meterTask?.cancel()
        inputLevel = 0
        do {
            audioURL = try recorder.stop()
            guard let audioURL else { return }
            guard session.transition(to: .processing, for: id) else { return }
            if interactionSounds { NSSound(named: "Pop")?.play() }
            pendingInput = .audio(audioURL)
            process(.audio(audioURL), id: id)
        } catch { fail(error.localizedDescription, id: id) }
    }

    func retryProcessing() {
        guard !hasUncommittedEdits, canRetry, let pendingInput, let id = session.beginProcessing() else { return }
        // A retry can happen much later: let the user decide where to insert its result.
        shouldInsertAfterProcessing = false
        presentationDismissed = false
        process(pendingInput, id: id)
    }

    /// Reuses text explicitly chosen in the editor, without recording or automatic insertion.
    func reprocessDraft(source: DraftSource, mode: DictationMode, style: OutputStyle, language: OutputLanguage) {
        guard mode != .ask, !hasUncommittedEdits, !phase.isActive, !isInserting, let draft,
              let id = session.beginProcessing() else { return }
        recordedMode = mode
        recordedAskContext = AskContext()
        completionDisposition = .copyNeeded
        presentationDismissed = false
        recordedOptions = ProcessingOptions(targetLanguage: language, dictionary: library.dictionary, style: style)
        shouldInsertAfterProcessing = false
        let input = ProcessingInput.text(draft.sourceText(source))
        pendingInput = input
        process(input, id: id)
    }

    /// Commits a local edit; no API request or paste is triggered.
    @discardableResult
    func saveDraftEdits() -> Bool {
        guard !phase.isActive, !isInserting else { return false }
        guard hasUncommittedEdits else { return draft != nil }
        guard draft?.edit(editorText) == true else {
            statusMessage = "文字不能为空，请填写内容或放弃修改。"
            return false
        }
        pendingInput = nil
        if let result { saveHistory(result) }
        statusMessage = "修改已保留，可复制或插入"
        return true
    }

    func discardDraftEdits() { editorText = draft?.text ?? "" }

    func restorePreviousDraft() {
        guard !hasUncommittedEdits, !phase.isActive, !isInserting, draft?.canRestorePrevious == true else { return }
        draft?.restorePrevious()
        editorText = draft?.text ?? ""
        pendingInput = nil
        if let result { saveHistory(result) }
        statusMessage = "已恢复上一版文字"
    }

    func copyOriginalTranscription() {
        guard let draft else { return }
        NSPasteboard.general.clearContents()
        statusMessage = NSPasteboard.general.setString(draft.transcription, forType: .string)
            ? "已复制原始转写" : "复制失败，请选择原始文字手动复制"
    }

    private func process(_ input: ProcessingInput, id: UUID) {
        guard let apiKey = keychain.read(), !apiKey.isEmpty else {
            fail(PithError.missingAPIKey.localizedDescription, id: id)
            return
        }
        statusMessage = input.isText ? "正在整理文字，无需重新录音…" : "正在识别，可按 Esc 取消"
        notifySessionChange()
        let provider = ProviderClient(configuration: configuration, apiKey: apiKey)
        let selectedMode = recordedMode
        let selectedOptions = recordedOptions
        let askContext = recordedAskContext
        let speechSource = recordedSpeechSource
        let speechLocale = recordedSpeechLocale
        let settings = DraftSettings(mode: selectedMode, style: selectedOptions.style, language: selectedOptions.targetLanguage)
        processingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await input.transcription { url in
                    if speechSource == .system {
                        return try await SystemTranscriber().transcribe(audioURL: url, locale: speechLocale,
                                                                        words: selectedOptions.dictionary.words)
                    }
                    return try await provider.transcribe(audioURL: url, options: selectedOptions)
                }
                try Task.checkCancellation()
                guard session.isCurrent(id) else { return }
                pendingInput = .text(text)
                if draft == nil {
                    draft = TextDraft(transcription: text, settings: settings)
                    editorText = text
                }
                // Recognition is the expensive, non-repeatable stage. Retain its text immediately.
                discardAudio()
                if let result { saveHistory(result) }
                statusMessage = selectedMode == .ask ? "正在处理你的问题或编辑要求…" : "原文已保留，正在整理文字…"
                notifySessionChange()
                let output: ProviderResult
                var asksForInsertion = false
                var disposition = CompletionDisposition.copyNeeded
                if selectedMode == .ask {
                    let response = try await provider.ask(instruction: text, context: askContext)
                    output = ProviderResult(transcription: text, text: response.text)
                    asksForInsertion = response.action != .answer
                    disposition = asksForInsertion ? .copyNeeded : .answer
                } else {
                    output = try await provider.process(transcription: text, mode: selectedMode, options: selectedOptions)
                }
                try Task.checkCancellation()
                guard session.isCurrent(id) else { return }
                completionDisposition = disposition
                if let warning = output.refinementWarning {
                    fail("文字整理未完成，当前文字已保留。\(warning)", id: id)
                    return
                }
                draft?.apply(output, settings: settings)
                editorText = draft?.text ?? ""
                pendingInput = nil
                if let result { saveHistory(result) }
                var message = "文字已就绪，可复制或插入"
                let wantsInsertion = shouldInsertAfterProcessing && (selectedMode != .ask || asksForInsertion)
                if wantsInsertion, let capturedTarget {
                    guard session.transition(to: .inserting, for: id) else { return }
                    statusMessage = "正在回填原输入框…"
                    notifySessionChange()
                    let outcome = await PasteboardInserter.insert(output.text, into: capturedTarget, automatically: true)
                    try Task.checkCancellation()
                    guard session.isCurrent(id) else { return }
                    if case .sent = outcome { completionDisposition = .inserted }
                    message = insertionMessage(outcome)
                } else if wantsInsertion {
                    message = "文字已保留；未确认原输入框，请复制后粘贴"
                } else if selectedMode == .ask {
                    message = "回答已就绪"
                }
                guard session.transition(to: .completed, for: id) else { return }
                statusMessage = message
                notifySessionChange()
            } catch is CancellationError {
                // Explicit cancellation invalidates the ID; an unexpected provider cancellation
                // still needs a terminal state so the controls do not stay disabled indefinitely.
                guard session.isCurrent(id) else { return }
                fail("处理已中断，已有文字已保留，请重试。", id: id)
            } catch {
                guard session.isCurrent(id) else { return }
                fail(error.localizedDescription, id: id)
            }
        }
    }

    func cancel() {
        session.cancel()
        startTask?.cancel()
        processingTask?.cancel()
        insertionTask?.cancel()
        meterTask?.cancel()
        recorder.cancel()
        interaction.reset()
        isInserting = false
        inputLevel = 0
        if pendingInput?.isText != true { pendingInput = nil }
        discardAudio()
        statusMessage = result == nil ? "已取消，可以重新开始" : "文字已保留，可复制"
        notifySessionChange()
    }

    func copyResult() {
        guard !hasUncommittedEdits, let text = result?.text else { return }
        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.setString(text, forType: .string)
        statusMessage = copied ? "已复制到剪贴板" : "复制失败，请从结果中选择文字复制"
    }

    func insertResult() {
        guard !hasUncommittedEdits, let text = result?.text, !phase.isActive, !isInserting else { return }
        guard let capturedTarget else {
            copyResult()
            statusMessage = "未确认原输入框，已复制；请手动粘贴"
            return
        }
        isInserting = true
        insertionTask = Task { [weak self] in
            let outcome = await PasteboardInserter.insert(text, into: capturedTarget, automatically: false)
            guard !Task.isCancelled, let self else { return }
            isInserting = false
            statusMessage = insertionMessage(outcome)
        }
    }

    func shutdown() {
        cancel()
        hotkey?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    private func insertionMessage(_ outcome: InsertionOutcome) -> String {
        switch outcome {
        case .sent: "已发送到输入框，可在菜单中查看本次文字"
        case let .unavailable(reason): "\(reason) 文字已保留，可复制。"
        }
    }

    private func shortcutPressed(trigger: String, intent: ShortcutIntent, isFunction: Bool) {
        let activation: ShortcutActivationMode = isFunction || (phase == .recording && !recordingUsesHold)
            ? .toggle : activationMode
        let action = interaction.keyPressed(phase: phase, trigger: trigger, activation: activation)
        if action == .start {
            let title = isFunction ? "Fn" : additionalShortcuts.first { $0.id.uuidString == trigger }?.title ?? shortcut.title
            startRecording(modeOverride: intent.mode, triggerTitle: title, usesHold: !isFunction && activationMode == .hold)
        } else { perform(action) }
    }
    private func shortcutReleased(trigger: String) {
        perform(interaction.keyReleased(phase: phase, trigger: trigger))
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .none: break
        case .start: startRecording()
        case .stop: stopRecordingAndProcess()
        case .cancel: cancel()
        }
    }

    private func notifySessionChange() {
        hotkey?.setSessionActive(phase.isActive || presentation != .hidden)
        onSessionChange?()
    }

    func dismissPresentation() {
        guard !phase.isActive else { return }
        presentationDismissed = true
        notifySessionChange()
    }

    private func fail(_ message: String, id: UUID) {
        guard session.transition(to: .failed(message), for: id) else { return }
        statusMessage = message
        interaction.reset()
        inputLevel = 0
        meterTask?.cancel()
        notifySessionChange()
    }

    private func rememberFrontmostApplication() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        lastActiveApplication = app
    }

    private func startMetering(id: UUID) {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, session.isCurrent(id), phase == .recording else { return }
                let sample = recorder.sample()
                recordingDuration = sample.duration
                inputLevel = sample.level
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
        }
    }

    private func discardAudio() {
        guard let audioURL else { return }
        do { try FileManager.default.removeItem(at: audioURL) }
        catch { logger.error("Could not remove temporary dictation audio") }
        self.audioURL = nil
    }
}

private extension UserDefaults {
    func decode<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func encode<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        set(data, forKey: key)
    }
}
