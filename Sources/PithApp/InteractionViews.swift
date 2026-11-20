import AppKit
import PithCore
import SwiftUI

struct MenuBarView: View {
    @Bindable var model: PithAppModel
    let onOpenSettings: @MainActor () -> Void
    let onOpenLibrary: @MainActor () -> Void
    let onOpenEditor: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Pith", systemImage: "waveform").font(.title3.bold())
                Spacer()
                Text(model.phase.isActive ? "使用中" : "随时说话")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("模式", selection: $model.mode) {
                ForEach(DictationMode.voiceModes) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(model.phase.isActive)
            if model.mode != .ask {
                Picker("表达风格", selection: $model.outputStyle) {
                    ForEach(OutputStyle.allCases) { Text($0.title).tag($0) }
                }.disabled(model.phase.isActive)
            } else {
                Text("选中文字后说出修改要求或问题；也可以直接提问。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.mode == .translate {
                Picker("翻译成", selection: $model.targetLanguage) {
                    ForEach(OutputLanguage.allCases) { Text($0.title).tag($0) }
                }
                .disabled(model.phase.isActive)
            }

            if !model.apiKeyIsConfigured {
                readinessNote("先配置 API，即可开始语音输入", action: "前往设置", onAction: onOpenSettings)
            } else if let error = model.shortcutError {
                readinessNote(error, action: "修改快捷键", onAction: onOpenSettings)
            } else if !model.accessibilityAuthorized {
                readinessNote("开启辅助功能后，可自动回填原输入框", action: "去开启") {
                    model.openPermissionSettings(microphone: false)
                }
            }

            HStack {
                Button(action: primaryAction) {
                    Label(primaryTitle, systemImage: model.phase == .recording ? "stop.fill" : "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.phase == .recording ? .red : .accentColor)
                .disabled((model.phase.isActive && model.phase != .recording) || model.isInserting || model.hasUncommittedEdits)
                if model.phase.isActive {
                    Button("取消") { model.cancel() }
                }
            }
            if model.phase == .recording {
                RecordingMeter(level: model.inputLevel, duration: model.recordingDuration)
            } else if model.phase.isActive {
                ProgressView().controlSize(.small)
            }

            Text(model.statusMessage)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if model.canRetry {
                Button(model.retryTitle) { model.retryProcessing() }
                    .disabled(model.hasUncommittedEdits)
            }
            if let result = model.result {
                if result.refinementWarning != nil {
                    Label("原始转写 · 尚未整理或翻译", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                ScrollView {
                    Text(result.text).font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        .padding(10)
                }
                .frame(height: 110)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("识别结果")
                HStack {
                    Button("复制文字", systemImage: "doc.on.doc") { model.copyResult() }
                        .disabled(model.hasUncommittedEdits)
                    Spacer()
                    Button(model.isInserting ? "正在插入…" : "插入原应用") { model.insertResult() }
                        .disabled(model.phase.isActive || model.isInserting || model.hasUncommittedEdits)
                }
                Button(model.hasUncommittedEdits ? "继续编辑 · 有未保存修改" : "编辑、换风格或再次翻译…",
                       systemImage: "square.and.pencil") { onOpenEditor() }
            }
            Divider()
            Text(model.shortcutHint).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("设置…", systemImage: "gearshape") { onOpenSettings() }
                Button("词典与历史", systemImage: "books.vertical") { onOpenLibrary() }
                Spacer()
                Button("退出 Pith") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain).font(.caption)
        }
        .padding(16).frame(width: 350)
    }

    private var primaryTitle: String {
        switch model.phase {
        case .recording: model.sessionMode == .ask ? "结束并处理" : "结束并输入"
        case .requestingPermission: "正在准备麦克风…"
        case .processing: "正在识别并整理…"
        case .inserting: "正在回填…"
        default: model.result == nil ? "开始说话" : "再说一段"
        }
    }

    private func primaryAction() {
        if model.phase == .recording { model.stopRecordingAndProcess() }
        else { model.startRecording() }
    }

    private func readinessNote(
        _ message: String,
        action: String,
        onAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: "info.circle").font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Button(action, action: onAction).font(.caption)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SessionOverlayView: View {
    @Bindable var model: PithAppModel
    let onOpenSettings: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void
    let onOpenEditor: @MainActor () -> Void

    var body: some View {
        if model.presentation == .resultCard {
            ResultCardView(model: model, onDismiss: onDismiss)
        } else {
            VoiceBarView(model: model, onOpenSettings: onOpenSettings,
                         onDismiss: onDismiss, onOpenEditor: onOpenEditor)
        }
    }
}

/// Recording and processing share one nonactivating panel and the same bottom anchor.
struct VoiceBarView: View {
    @Bindable var model: PithAppModel
    let onOpenSettings: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void
    let onOpenEditor: @MainActor () -> Void

    static func size(for phase: SessionPhase) -> NSSize {
        switch phase {
        case .recording: NSSize(width: RecordingCapsuleView.width, height: 68)
        case .requestingPermission, .processing, .inserting: NSSize(width: ThinkingCapsuleView.width, height: 68)
        default: NSSize(width: 360, height: 128)
        }
    }

    var body: some View {
        Group {
            if model.phase == .recording {
                RecordingCapsuleView(level: model.inputLevel, modeTitle: model.sessionMode.title,
                                     onCancel: { model.cancel() }, onFinish: { model.stopRecordingAndProcess() })
                    .contextMenu {
                        if model.sessionMode == .translate {
                            ForEach(OutputLanguage.allCases) { language in
                                Button {
                                    model.recordingTargetLanguage = language
                                } label: {
                                    if model.recordingTargetLanguage == language {
                                        Label(language.title, systemImage: "checkmark")
                                    } else { Text(language.title) }
                                }
                            }
                        }
                    }
                    .help(model.sessionMode == .translate
                          ? "翻译成 \(model.recordingTargetLanguage.title)；右键更改语言。Fn 完成，Esc 取消。"
                          : "\(model.sessionMode.title) · Fn 完成，Esc 取消")
            } else if model.phase.isActive {
                ThinkingCapsuleView(title: model.phase == .requestingPermission ? "准备中" : "Thinking")
                    .help("Esc 取消")
            } else {
                retainedTextView
            }
        }
    }

    private var retainedTextView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text(model.result == nil ? "这次未完成" : "文字已保留").font(.callout)
                Spacer()
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel("收起")
            }
            Text(model.statusMessage).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                if model.result != nil {
                    Button("复制文字") { model.copyResult() }.disabled(model.hasUncommittedEdits)
                    Button("查看文字", action: onOpenEditor)
                } else { Button("检查设置", action: onOpenSettings) }
                Spacer()
                if model.canRetry {
                    Button(model.retryTitle) { model.retryProcessing() }.disabled(model.hasUncommittedEdits)
                }
            }.controlSize(.mini)
        }
        .padding(12).frame(width: 360, height: 128)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.15)))
    }
}

struct RecordingCapsuleView: View {
    static let width: CGFloat = 232
    let level: Double
    let modeTitle: String
    let onCancel: @MainActor () -> Void
    let onFinish: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onCancel) {
                Image(systemName: "xmark").font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white).frame(width: 46, height: 46)
                    .background(.white.opacity(0.25), in: Circle())
            }.accessibilityLabel("取消录音")
            AudioWaveformView(level: level).frame(width: 88, height: 34)
            Button(action: onFinish) {
                Image(systemName: "checkmark").font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.black).frame(width: 46, height: 46)
                    .background(.white, in: Circle())
            }.accessibilityLabel("结束录音")
        }
        .buttonStyle(.plain).padding(8)
        .frame(width: Self.width, height: 68)
        .background(.black, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.38), lineWidth: 2))
        .accessibilityElement(children: .contain).accessibilityLabel("\(modeTitle)录音中")
    }
}

/// The microphone level controls amplitude; silence stays flat instead of showing fake activity.
struct AudioWaveformView: View {
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || level < 0.015)) { context in
            Canvas { canvas, size in
                let amplitude = max(0, min(1, level))
                let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                let count = 13
                let barWidth: CGFloat = 3
                let step = (size.width - barWidth) / CGFloat(count - 1)
                for index in 0..<count {
                    let envelope = 0.25 + 0.75 * sin(.pi * Double(index + 1) / Double(count + 1))
                    let pulse = 0.65 + 0.35 * sin(time * 10 + Double(index) * 1.7)
                    let height = 4 + (size.height - 4) * amplitude * envelope * pulse
                    let rect = CGRect(x: CGFloat(index) * step, y: (size.height - height) / 2,
                                      width: barWidth, height: height)
                    canvas.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(.white))
                }
            }
        }
        .accessibilityLabel(level > 0.03 ? "麦克风正在收音" : "等待声音")
    }
}

struct ThinkingCapsuleView: View {
    static let width: CGFloat = 188
    var title = "Thinking"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let fraction = reduceMotion ? 0.68 : 0.68 + 0.1 * sin(time * 2)
            ZStack(alignment: .leading) {
                Color.black
                Color.white.opacity(0.22).frame(width: Self.width * fraction)
                Text(title).font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72)).frame(maxWidth: .infinity)
            }
            .frame(width: Self.width, height: 68).clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 2))
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(title == "Thinking" ? "正在识别和处理语音" : title)
    }
}

struct ShortcutHintView: View {
    static let size = NSSize(width: 440, height: 264)

    var body: some View {
        VStack(spacing: 16) {
            Label("Pith 快捷键", systemImage: "waveform").font(.system(size: 20, weight: .semibold))
            HStack(spacing: 6) {
                Text("轻触一次开始说话。按")
                Text("Fn").fontWeight(.medium).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.18)))
                Text("来完成。")
            }.font(.system(size: 17)).foregroundStyle(.white.opacity(0.7))
            VStack(spacing: 0) {
                shortcutRow("口述", keys: ["Fn"])
                Divider().overlay(.black)
                shortcutRow("翻译", keys: ["Fn", "Left Shift"])
                Divider().overlay(.black)
                shortcutRow("问任何问题", keys: ["Fn", "Space"])
            }
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black, lineWidth: 1))
        }
        .padding(22).frame(width: Self.size.width, height: Self.size.height)
        .foregroundStyle(.white).background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("Pith 快捷键，松开 Fn 关闭")
    }

    private func shortcutRow(_ title: String, keys: [String]) -> some View {
        HStack(spacing: 0) {
            Text(title).font(.system(size: 18, weight: .medium))
                .frame(width: 150, alignment: .leading)
            Rectangle().fill(.black).frame(width: 1)
            HStack(spacing: 6) {
                ForEach(keys, id: \.self) { key in
                    Text(key).font(.system(size: 16, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.18)))
                }
            }.padding(.leading, 14).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.horizontal, 16).frame(height: 46)
    }
}

struct ResultCardView: View {
    @Bindable var model: PithAppModel
    let onDismiss: @MainActor () -> Void
    static let width: CGFloat = 420

    /// Fits short answers without a large empty panel while keeping long answers scrollable.
    static func height(for text: String) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: width - 36, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 14), .paragraphStyle: paragraph]
        )
        return min(360, max(144, ceil(bounds.height) + 102))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(model.completionDisposition == .answer ? "问任何问题" : "文字已就绪",
                      systemImage: model.completionDisposition == .answer ? "sparkles" : "text.alignleft")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel("关闭结果卡片")
            }
            ScrollView {
                Text(model.result?.text ?? "")
                    .font(.system(size: 14)).lineSpacing(4).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityLabel("Pith 回答")
            HStack {
                Text("Esc 收起").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("复制", systemImage: "doc.on.doc") { model.copyResult() }
                    .disabled(model.hasUncommittedEdits)
            }
        }
        .padding(18).frame(width: Self.width, height: Self.height(for: model.result?.text ?? ""))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.15)))
    }
}

private struct RecordingMeter: View {
    let level: Double
    let duration: TimeInterval

    var body: some View {
        HStack {
            LevelBars(level: level).frame(width: 90, height: 20)
            Text(durationText(duration)).monospacedDigit()
            Spacer()
            Text(level > 0.03 ? "正在收音" : "等待声音").foregroundStyle(.secondary)
        }.font(.caption)
    }
}

private struct LevelBars: View {
    let level: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<16) { index in
                Capsule()
                    .fill(Double(index) / 16 < level ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(width: 4, height: 6 + Double(index % 4) * 4)
            }
        }
        .accessibilityLabel(level > 0.03 ? "麦克风正在收音" : "未检测到声音")
    }
}

private func durationText(_ duration: TimeInterval) -> String {
    let seconds = max(0, Int(duration))
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

struct SettingsView: View {
    @Bindable var model: PithAppModel
    @State private var baseURL = ""
    @State private var transcriptionModel = ""
    @State private var textModel = ""
    @State private var apiKey = ""
    @State private var transcriptionSource: TranscriptionSource = .api
    @State private var speechLocale = "zh-CN"

    var body: some View {
        Form {
            Section("说话与输入") {
                Picker("默认表达风格", selection: $model.outputStyle) {
                    ForEach(OutputStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("翻译目标语言", selection: $model.targetLanguage) {
                    ForEach(OutputLanguage.allCases) { Text($0.title).tag($0) }
                }
                Toggle("完成后自动回填原输入框", isOn: $model.automaticallyInsert)
                Toggle("开始与结束提示音", isOn: $model.interactionSounds)
                Text("输入位置变化时保留文字供复制；快捷键设置立即生效。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(model.phase.isActive || model.isInserting)

            Section("快捷键") { ShortcutSettingsView(model: model) }
                .disabled(model.phase.isActive || model.isInserting)

            Section("权限与设备") {
                if model.configuration.transcriptionSource == .system {
                    permissionRow("语音识别", granted: model.speechAuthorized,
                                  detail: "优先使用设备端识别；系统不支持时可能由 Apple 在线处理") {
                        model.requestSpeechPermission()
                    }
                }
                permissionRow("麦克风", granted: model.microphoneAuthorized,
                              detail: "使用系统当前输入设备，录音条显示实时音量") {
                    model.requestMicrophonePermission()
                }
                permissionRow("辅助功能", granted: model.accessibilityAuthorized,
                              detail: "用于 Fn / 🌐 快捷键和自动回填；备用组合键无需此权限") {
                    model.openPermissionSettings(microphone: false)
                }
                Button("刷新权限状态") { model.refreshReadiness() }
            }

            Section("API") {
                Picker("语音识别方式", selection: $transcriptionSource) {
                    ForEach(TranscriptionSource.allCases) { Text($0.title).tag($0) }
                }
                if transcriptionSource == .system {
                    Picker("说话语言", selection: $speechLocale) {
                        Text("普通话（中国大陆）").tag("zh-CN")
                        Text("English (US)").tag("en-US")
                        Text("日本語").tag("ja-JP")
                        Text("粤语（香港）").tag("zh-HK")
                    }
                    Text("系统先将语音转成文字，再由下面的模型整理或翻译，无需转写 API Key。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField("Base URL", text: $baseURL)
                if transcriptionSource == .api { TextField("转写模型", text: $transcriptionModel) }
                TextField("文本模型", text: $textModel)
                SecureField(model.apiKeyIsConfigured ? "API Key 已保存，输入可替换" : "API Key", text: $apiKey)
                Text(transcriptionSource == .system
                     ? "Key 保存在 macOS Keychain。仅识别后的文字和词典发送到模型 API；语音识别由 macOS 处理。"
                     : "Key 保存在 macOS Keychain；录音和文本仅发送到以上地址。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if model.apiKeyIsConfigured {
                        Button("清除 Key", role: .destructive) { model.clearAPIKey() }
                    }
                    Spacer()
                    Button("保存 API 设置") {
                        model.saveSettings(baseURL: baseURL, transcriptionModel: transcriptionModel,
                                           textModel: textModel, apiKey: apiKey,
                                           transcriptionSource: transcriptionSource, speechLocale: speechLocale)
                        apiKey = ""
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
                if !model.settingsMessage.isEmpty {
                    Text(model.settingsMessage).font(.caption).textSelection(.enabled)
                }
            }
            .disabled(model.phase.isActive || model.isInserting)

            Section("隐私") {
                Toggle("保存本地历史", isOn: Binding(
                    get: { model.library.historyEnabled }, set: { model.setHistoryEnabled($0) }
                ))
                .disabled(!model.libraryAvailable)
                Text("默认关闭。开启后保留最近 100 条文字；关闭后停止保存，已有记录可在“词典与历史”中删除。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("口述和翻译不读取输入框内容。“问任何问题”仅在触发时读取你明确选中的文字，并随口述要求发送到模型；不读取整个窗口。语音识别成功即删除录音；识别失败时仅在本次会话保留，用于重试。取消、开始新录音或退出时删除录音。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("个人词典会随当前录音和文本发送给你配置的 API，历史记录不会作为上下文上传。")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.libraryMessage.isEmpty {
                    Text(model.libraryMessage).font(.caption).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 540, minHeight: 520, idealHeight: 700)
        .onAppear {
            baseURL = model.configuration.baseURL
            transcriptionModel = model.configuration.transcriptionModel
            textModel = model.configuration.textModel
            transcriptionSource = model.configuration.transcriptionSource
            speechLocale = model.configuration.speechLocale
            model.refreshReadiness()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshReadiness()
        }
    }

    private func permissionRow(_ title: String, granted: Bool, detail: String,
                               action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(granted ? Color.green : Color.orange)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(granted ? "管理" : "开启", action: action)
        }
    }
}
