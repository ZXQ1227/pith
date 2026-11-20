import AppKit
import Carbon
import PithCore
import SwiftUI

struct ShortcutSettingsView: View {
    @Bindable var model: PithAppModel
    @State private var capturing = false

    var body: some View {
        Group {
            Picker("主快捷键", selection: $model.shortcut) {
                ForEach(DictationShortcut.allCases) { Text($0.title).tag($0) }
            }
            if model.shortcut == .function {
                CoreShortcutRows()
                Text("轻按一次开始，再按 Fn 完成；不需要一直按住。Fn 与方向键等组合不会开始录音。")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.accessibilityAuthorized {
                    Button("开启辅助功能，启用 Fn") { model.openPermissionSettings(microphone: false) }
                }
            }
            Picker("组合键触发方式", selection: $model.activationMode) {
                ForEach(ShortcutActivationMode.allCases) { Text($0.title).tag($0) }
            }
            Text("此选项只影响组合键；Fn 始终单按开始 / 结束。所有模式都可用录音条结束，Esc 取消。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(model.additionalShortcuts) { binding in
                HStack {
                    Text(binding.intent.title)
                    Spacer()
                    Text(binding.title).monospaced().foregroundStyle(.secondary)
                    Button { model.removeShortcut(binding.id) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).help("移除这个备用快捷键")
                        .accessibilityLabel("移除 \(binding.intent.title) \(binding.title)")
                }
            }
            Button("添加快捷键…", systemImage: "plus") { capturing = true }
            if let error = model.shortcutError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            if !model.shortcutSettingsMessage.isEmpty {
                Text(model.shortcutSettingsMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $capturing) { ShortcutCaptureSheet(model: model) }
    }
}

struct CoreShortcutRows: View {
    var body: some View {
        VStack(spacing: 14) {
            row("口述", detail: "杂乱的想法 → 清晰的文字", keys: ["Fn"], tint: .secondary)
            Divider()
            row("翻译", detail: "自然的语言 → 清晰、地道的写作", keys: ["Fn", "Left Shift"], tint: .blue)
            Divider()
            row("问任何问题", detail: "编辑或询问文本", keys: ["Fn", "Space"], tint: .green)
        }.padding(.vertical, 8)
    }

    private func row(_ title: String, detail: String, keys: [String], tint: Color) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                ForEach(keys, id: \.self) { key in
                    Text(key).font(.system(.body, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.secondary.opacity(0.65)))
                }
            }.frame(width: 160, alignment: .leading)
        }
    }
}

private struct ShortcutCaptureSheet: View {
    @Bindable var model: PithAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var intent: ShortcutIntent = .dictate
    @State private var captured: ShortcutBinding?
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("添加一个快捷键").font(.title2.bold())
            Picker("用于", selection: $intent) {
                ForEach(ShortcutIntent.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            ShortcutCaptureField(onCapture: { key, modifiers, label in
                let candidate = ShortcutBinding(keyCode: key, modifiers: modifiers, keyLabel: label, intent: intent)
                do { try candidate.validate(); captured = candidate; message = "" }
                catch { captured = nil; message = error.localizedDescription }
            }, onCancel: { dismiss() }, onInvalid: { error in captured = nil; message = error })
            .frame(height: 70)
            .overlay {
                Text(captured?.title ?? "点击这里，按下想用的组合键")
                    .font(.title3.monospaced()).allowsHitTesting(false)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            Text("支持外接键盘。使用 Control、Option 或多个修饰键搭配普通按键，按 Esc 放弃。录入期间暂停 Pith 的全局快捷键。")
                .font(.callout).foregroundStyle(.secondary)
            if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.orange) }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("添加") {
                    guard let captured else { return }
                    let binding = ShortcutBinding(keyCode: captured.keyCode, modifiers: captured.modifiers,
                                                  keyLabel: captured.keyLabel, intent: intent)
                    if model.addShortcut(binding) { dismiss() }
                    else { message = model.shortcutSettingsMessage }
                }
                .buttonStyle(.borderedProminent).disabled(captured == nil)
            }
        }
        .padding(24).frame(width: 420)
        .onAppear { model.setShortcutCaptureActive(true) }
        .onDisappear { model.setShortcutCaptureActive(false) }
    }
}

private struct ShortcutCaptureField: NSViewRepresentable {
    let onCapture: (UInt16, ShortcutModifiers, String) -> Void
    let onCancel: () -> Void
    let onInvalid: (String) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        view.onInvalid = onInvalid
        return view
    }
    func updateNSView(_ view: CaptureView, context: Context) {
        view.onCapture = onCapture
        view.onCancel = onCancel
        view.onInvalid = onInvalid
    }

    final class CaptureView: NSView {
        var onCapture: ((UInt16, ShortcutModifiers, String) -> Void)?
        var onCancel: (() -> Void)?
        var onInvalid: ((String) -> Void)?
        private var functionPressed = false
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
            setAccessibilityRole(.textField)
            setAccessibilityLabel("快捷键录入区域")
        }
        override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
        override func flagsChanged(with event: NSEvent) {
            if event.keyCode == kVK_Function { functionPressed = event.modifierFlags.contains(.function) }
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }
        override func keyDown(with event: NSEvent) {
            guard !event.isARepeat else { return }
            if event.keyCode == kVK_Escape { onCancel?(); return }
            guard !functionPressed else {
                onInvalid?("Fn 使用固定的口述、翻译和问答操作；备用快捷键请使用 Control、Option 或 Command 组合。")
                return
            }
            let names: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 117: "⌦",
                123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
                122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
                101: "F9", 109: "F10", 103: "F11", 111: "F12"]
            let label = names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
            onCapture?(event.keyCode, ShortcutModifiers(eventFlags: event.modifierFlags), label)
        }
    }
}
