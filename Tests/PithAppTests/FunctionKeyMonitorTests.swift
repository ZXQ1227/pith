import AppKit
import Carbon
import PithCore
import Testing
@testable import PithApp

@Suite("Fn Space event consumption")
struct FunctionKeyMonitorTests {
    @MainActor
    @Test("Space down, repeats and up are consumed regardless of release order", arguments: [true, false])
    func noSpaceLeaks(releaseFunctionFirst: Bool) async throws {
        var intents: [ShortcutIntent] = []
        let monitor = FunctionKeyMonitor(onTrigger: { intents.append($0) }, ordinaryKeyIsDown: { false })
        let fnDown = try event(key: kVK_Function, down: true, flags: .maskSecondaryFn)
        let fnUp = try event(key: kVK_Function, down: false)
        let spaceDown = try event(key: kVK_Space, down: true, flags: .maskSecondaryFn)
        let spaceUp = try event(key: kVK_Space, down: false)
        #expect(monitor.handle(.flagsChanged, event: fnDown))
        #expect(monitor.handle(.keyDown, event: spaceDown))
        #expect(monitor.handle(.keyDown, event: spaceDown))
        if releaseFunctionFirst {
            #expect(monitor.handle(.flagsChanged, event: fnUp))
            #expect(monitor.handle(.keyUp, event: spaceUp))
        } else {
            #expect(monitor.handle(.keyUp, event: spaceUp))
            #expect(monitor.handle(.flagsChanged, event: fnUp))
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(intents == [.ask])
        #expect(!monitor.handle(.keyDown, event: try event(key: kVK_Space, down: true)))
        #expect(!monitor.handle(.keyUp, event: spaceUp))
    }

    /// Creates metadata-only test events; no event is posted to macOS or another application.
    private func event(key: Int, down: Bool, flags: CGEventFlags = []) throws -> CGEvent {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: down))
        event.flags = flags
        return event
    }
}
