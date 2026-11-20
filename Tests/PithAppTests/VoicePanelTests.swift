import AppKit
import Testing
@testable import PithApp

@Suite("Voice panel focus")
struct VoicePanelTests {
    @MainActor
    @Test("the recording panel cannot become key or main; only clicked answer cards can accept focus")
    func nonactivatingRecordingPanel() {
        _ = NSApplication.shared
        let panel = VoicePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        panel.allowsKeyFocus = true
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        panel.close()
    }
}
