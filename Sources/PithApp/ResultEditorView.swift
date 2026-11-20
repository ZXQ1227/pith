import PithCore
import SwiftUI

struct ResultEditorView: View {
    @Bindable var model: PithAppModel
    @State private var source: DraftSource = .current
    @State private var mode: DictationMode = .rewrite
    @State private var style: OutputStyle = .natural
    @State private var language: OutputLanguage = .simplifiedChinese
    @State private var showOriginal = false

    private var busy: Bool { model.phase.isActive || model.isInserting }
    private var isBlank: Bool { model.editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("把这段话改到满意").font(.title2.bold())
                    Text("直接修改，或换种表达；原始转写始终保留。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Label("本次文字", systemImage: "text.bubble").foregroundStyle(.secondary)
            }

            if model.draft != nil {
                processingControls
                HStack {
                    Text("当前文字").font(.headline)
                    if model.hasUncommittedEdits {
                        Text("未保存修改").font(.caption).foregroundStyle(.orange)
                    }
                    Spacer()
                    Text("\(model.editorText.count) 字符").font(.caption).foregroundStyle(.secondary)
                    if model.hasUncommittedEdits {
                        Button("放弃修改") { model.discardDraftEdits() }
                        Button("保存修改") { model.saveDraftEdits() }.disabled(isBlank)
                    }
                }
                .disabled(busy)
                TextEditor(text: $model.editorText)
                    .font(.system(size: 15)).lineSpacing(5)
                    .scrollContentBackground(.hidden)
                    .padding(10).frame(minHeight: 180)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    .disabled(busy)
                    .accessibilityLabel("编辑当前文字")

                DisclosureGroup("原始转写", isExpanded: $showOriginal) {
                    VStack(alignment: .leading, spacing: 8) {
                        ScrollView {
                            Text(model.draft?.transcription ?? "")
                                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }.frame(maxHeight: 120)
                        Button("复制原文", systemImage: "doc.on.doc") { model.copyOriginalTranscription() }
                    }.padding(.top, 8)
                }

                HStack(alignment: .top) {
                    if model.phase.isActive { ProgressView().controlSize(.small) }
                    Text(model.statusMessage).font(.callout).foregroundStyle(.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if model.phase.isActive {
                        Button("取消") { model.cancel() }
                    } else if model.canRetry {
                        Button(model.retryTitle) { model.retryProcessing() }
                            .disabled(model.hasUncommittedEdits)
                    }
                }
                Divider()
                HStack {
                    Button("恢复上一版", systemImage: "arrow.uturn.backward") { model.restorePreviousDraft() }
                        .disabled(model.draft?.canRestorePrevious != true || model.hasUncommittedEdits)
                    Spacer()
                    Button(model.hasUncommittedEdits ? "保存并复制" : "复制文字") {
                        if model.saveDraftEdits() { model.copyResult() }
                    }
                    .disabled(isBlank)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    Button(model.hasUncommittedEdits ? "保存并插入" : "插入原应用") {
                        if model.saveDraftEdits() { model.insertResult() }
                    }
                    .buttonStyle(.borderedProminent).disabled(isBlank)
                }
                .disabled(busy)
                Text(model.library.historyEnabled
                     ? "已保存的修改会更新本条本地历史。重新整理后，请确认文字再复制或插入。"
                     : "历史保存已关闭，本次文字仅保留到下一次录音或退出。重新整理后请确认再使用。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("还没有可编辑的文字", systemImage: "mic",
                                       description: Text("用快捷键说一段话，识别后即可在这里继续修改。"))
            }
        }
        .padding(24).frame(minWidth: 640, minHeight: 620)
        .onAppear(perform: loadDraftSettings)
        .onChange(of: model.draft?.settings) { loadDraftSettings() }
    }

    private var processingControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Picker("处理方式", selection: $mode) {
                    ForEach(DictationMode.textModes) { Text($0.title).tag($0) }
                }
                Picker("表达风格", selection: $style) {
                    ForEach(OutputStyle.allCases) { Text($0.title).tag($0) }
                }
            }
            HStack(spacing: 16) {
                Picker("使用", selection: $source) {
                    ForEach(DraftSource.allCases) { Text($0.title).tag($0) }
                }
                if mode == .translate {
                    Picker("翻译成", selection: $language) {
                        ForEach(OutputLanguage.allCases) { Text($0.title).tag($0) }
                    }
                }
                Spacer(minLength: 0)
                Button(mode == .translate ? "生成译文" : "重新整理", systemImage: "wand.and.stars") {
                    if model.saveDraftEdits() {
                        model.reprocessDraft(source: source, mode: mode, style: style, language: language)
                    }
                }
                .disabled(isBlank)
            }
            Text("只处理所选文字，无需重新录音。未保存的修改会先保留为一版，再进行处理。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .disabled(busy)
    }

    private func loadDraftSettings() {
        guard let settings = model.draft?.settings else { return }
        mode = settings.mode == .ask ? .rewrite : settings.mode
        style = settings.style
        language = settings.language
    }
}
