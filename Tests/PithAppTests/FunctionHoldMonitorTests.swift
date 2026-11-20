import AppKit
import Carbon
import PithCore
import Testing
@testable import PithApp

@Suite("Fn hold timer lifecycle")
struct FunctionHoldMonitorTests {
    @MainActor
    @Test("a held Fn shows help then releases it without triggering dictation")
    func showAndRelease() async throws {
        var hints: [Bool] = []
        var intents: [ShortcutIntent] = []
        let monitor = FunctionKeyMonitor(onTrigger: { intents.append($0) }, onHintChange: { hints.append($0) },
                                         holdDelay: .zero, ordinaryKeyIsDown: { false })
        _ = monitor.handle(.flagsChanged, event: try fnEvent(down: true))
        for _ in 0..<100 {
            if hints == [true] { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(hints == [true])
        _ = monitor.handle(.flagsChanged, event: try fnEvent(down: false))
        await drainMainQueue()
        #expect(hints == [true, false])
        #expect(intents.isEmpty)
    }

    @MainActor
    @Test("a quick tap cancels the timer; a recording can still end with held Fn")
    func tapAndActiveRecording() async throws {
        for canShow in [true, false] {
            var hints: [Bool] = []
            var intents: [ShortcutIntent] = []
            let monitor = FunctionKeyMonitor(onTrigger: { intents.append($0) }, onHintChange: { hints.append($0) },
                                             canShowHint: { canShow }, holdDelay: .zero,
                                             ordinaryKeyIsDown: { false })
            _ = monitor.handle(.flagsChanged, event: try fnEvent(down: true))
            if !canShow { try await Task.sleep(for: .milliseconds(10)) }
            _ = monitor.handle(.flagsChanged, event: try fnEvent(down: false))
            await drainMainQueue()
            #expect(hints.isEmpty)
            #expect(intents == [.dictate])
        }
    }

    @MainActor
    @Test("sleep or permission reset cancels a pending hint")
    func resetBeforeThreshold() async throws {
        var hints: [Bool] = []
        let monitor = FunctionKeyMonitor(onTrigger: { _ in Issue.record("Reset must not trigger") },
                                         onHintChange: { hints.append($0) }, holdDelay: .zero,
                                         ordinaryKeyIsDown: { false })
        _ = monitor.handle(.flagsChanged, event: try fnEvent(down: true))
        monitor.resetGesture()
        await drainMainQueue()
        #expect(hints.isEmpty)
    }

    /// Constructs metadata only; these events are never posted to macOS.
    private func fnEvent(down: Bool) throws -> CGEvent {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Function), keyDown: down))
        event.flags = down ? .maskSecondaryFn : []
        return event
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
