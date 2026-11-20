import PithCore
import SwiftUI

struct LibraryView: View {
    @Bindable var model: PithAppModel

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                DictionaryView(model: model)
                    .tabItem { Label("个人词典", systemImage: "character.book.closed") }
                HistoryView(model: model)
                    .tabItem { Label("历史记录", systemImage: "clock.arrow.circlepath") }
            }
            if !model.libraryMessage.isEmpty {
                Divider()
                Text(model.libraryMessage).font(.callout).foregroundStyle(.secondary)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 440)
    }
}

private struct DictionaryView: View {
    @Bindable var model: PithAppModel
    @State private var newWord = ""
    @State private var query = ""

    private var words: [String] {
        model.library.dictionary.words.filter { query.isEmpty || $0.localizedStandardContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("让 Pith 更懂你的用词").font(.title2.bold())
            Text("添加人名、产品名或专业术语，例如 Pith、Typeless、飞书。词语会作为识别与整理提示发送到你配置的 API。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("输入一个词语", text: $newWord).onSubmit(addWord)
                    .accessibilityLabel("新词语")
                Button("添加", action: addWord).buttonStyle(.borderedProminent)
                    .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .disabled(!model.libraryAvailable)
            HStack {
                TextField("搜索词典", text: $query)
                Text("\(model.library.dictionary.words.count) / \(PersonalDictionary.maximumWords)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if words.isEmpty {
                ContentUnavailableView(query.isEmpty ? "还没有专属词语" : "没有匹配的词语",
                                       systemImage: "character.book.closed",
                                       description: Text(query.isEmpty ? "添加后从下一次录音开始生效。" : "试试其他关键词。"))
            } else {
                List(words, id: \.self) { word in
                    HStack {
                        Text(word).textSelection(.enabled)
                        Spacer()
                        Button {
                            model.removeDictionaryWord(word)
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).help("从词典移除")
                        .accessibilityLabel("移除词语 \(word)")
                    }.padding(.vertical, 4)
                }
            }
        }
        .padding(16)
    }

    private func addWord() {
        if model.addDictionaryWord(newWord) { newWord = "" }
    }
}

private struct HistoryView: View {
    @Bindable var model: PithAppModel
    @State private var query = ""
    @State private var confirmClear = false
    @State private var pendingDeletion: HistoryEntry?

    private var entries: [HistoryEntry] { model.library.history.filter { $0.matches(query) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("说过的话，随时找回").font(.title2.bold())
                Spacer()
                Toggle("保存历史", isOn: Binding(
                    get: { model.library.historyEnabled }, set: { model.setHistoryEnabled($0) }
                ))
                .toggleStyle(.switch).disabled(!model.libraryAvailable)
            }
            Text(model.library.historyEnabled
                 ? "仅在本机保留最近 100 条文字，不保存音频，也不上传历史。"
                 : "当前不会保存新记录。已有记录保留，可单独删除或全部清空。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("搜索原始转写或整理结果", text: $query)
                Button("清空历史", role: .destructive) { confirmClear = true }
                    .disabled(model.library.history.isEmpty || !model.libraryAvailable)
            }
            if entries.isEmpty {
                ContentUnavailableView(query.isEmpty ? "还没有历史记录" : "没有匹配的记录",
                                       systemImage: "clock.arrow.circlepath",
                                       description: Text(query.isEmpty ? "开启保存后，新完成的转写会出现在这里。" : "试试原话中的关键词。"))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(entries) { entry in
                            historyCard(entry)
                        }
                    }
                }
            }
        }
        .padding(16)
        .alert("清空全部历史？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { model.clearHistory() }
        } message: {
            Text("将永久删除本机的 \(model.library.history.count) 条文字记录，个人词典不受影响。")
        }
        .alert("删除这条记录？", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("取消", role: .cancel) { pendingDeletion = nil }
            Button("删除", role: .destructive) {
                if let entry = pendingDeletion { model.removeHistory(entry.id) }
                pendingDeletion = nil
            }
        } message: { Text("将永久删除这条记录的原始转写和整理结果。") }
    }

    private func historyCard(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.mode.title)
                if let style = entry.outputStyle, style != .natural { Text(style.title) }
                if let language = entry.targetLanguage { Text("→ \(language.title)") }
                if !entry.isRefined { Text("仅原始转写").foregroundStyle(.orange) }
                Spacer()
                Text(entry.createdAt, format: .dateTime.month().day().hour().minute())
            }.font(.caption).foregroundStyle(.secondary)
            Text(entry.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            if entry.text != entry.transcription {
                DisclosureGroup("查看原始转写") {
                    Text(entry.transcription).font(.callout).foregroundStyle(.secondary)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack {
                Button("复制文字", systemImage: "doc.on.doc") { model.copyHistory(entry) }
                Spacer()
                Button("删除", role: .destructive) { pendingDeletion = entry }
            }.controlSize(.small)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
