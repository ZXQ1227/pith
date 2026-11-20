import Foundation
import Testing
@testable import PithCore

@Suite("Fn gestures and shortcut bindings")
struct FunctionKeyGestureTests {
    @Test("a bare Fn tap triggers once on release, without requiring a long hold")
    func bareTap() {
        var gesture = FunctionKeyGesture()
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: true, leftShiftDown: false, otherModifiersDown: false) == nil)
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: true, leftShiftDown: false, otherModifiersDown: false) == nil)
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false, leftShiftDown: false, otherModifiersDown: false) == .dictate)
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false, leftShiftDown: false, otherModifiersDown: false) == nil)
    }

    @Test("left Shift can precede or follow Fn, and releasing Shift first retains translation intent")
    func translationChord() {
        for shiftFirst in [false, true] {
            var gesture = FunctionKeyGesture()
            _ = gesture.flagsChanged(isFunctionEvent: true, functionDown: true, leftShiftDown: shiftFirst, otherModifiersDown: false)
            _ = gesture.flagsChanged(isFunctionEvent: false, functionDown: true, leftShiftDown: true, otherModifiersDown: false)
            _ = gesture.flagsChanged(isFunctionEvent: false, functionDown: true, leftShiftDown: false, otherModifiersDown: false)
            #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false, leftShiftDown: false, otherModifiersDown: false) == .translate)
        }
    }

    @Test("Fn with arrows, function keys or other unreserved keys never starts dictation")
    func ignoresOtherChords() {
        var gesture = FunctionKeyGesture()
        _ = gesture.flagsChanged(isFunctionEvent: true, functionDown: true, leftShiftDown: false, otherModifiersDown: false)
        gesture.ordinaryKeyPressed()
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false, leftShiftDown: false, otherModifiersDown: false) == nil)
        _ = gesture.flagsChanged(isFunctionEvent: true, functionDown: true, leftShiftDown: false, otherModifiersDown: false)
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false, leftShiftDown: false, otherModifiersDown: false) == .dictate)
    }

    @Test("Fn Space fires Ask once on Fn release, including repeated Space downs")
    func askChord() {
        var gesture = FunctionKeyGesture()
        #expect(gesture.spacePressed() == false)
        _ = gesture.flagsChanged(isFunctionEvent: true, functionDown: true, leftShiftDown: false, otherModifiersDown: false)
        #expect(gesture.spacePressed() == true)
        #expect(gesture.spacePressed() == true)
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false, leftShiftDown: false, otherModifiersDown: false) == .ask)
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false, leftShiftDown: false, otherModifiersDown: false) == nil)
        #expect(gesture.spacePressed() == false)
    }

    @Test("Ask cannot be mixed with Shift or another ordinary key")
    func ambiguousAskChords() {
        for shiftFirst in [true, false] {
            var gesture = FunctionKeyGesture()
            _ = gesture.flagsChanged(isFunctionEvent: true, functionDown: true, leftShiftDown: shiftFirst, otherModifiersDown: false)
            _ = gesture.spacePressed()
            _ = gesture.flagsChanged(isFunctionEvent: false, functionDown: true, leftShiftDown: true, otherModifiersDown: false)
            #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false, leftShiftDown: false, otherModifiersDown: false) == nil)
        }
        var gesture = FunctionKeyGesture()
        _ = gesture.flagsChanged(isFunctionEvent: true, functionDown: true, leftShiftDown: false, otherModifiersDown: false)
        #expect(gesture.spacePressed() == true)
        gesture.ordinaryKeyPressed()
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false, leftShiftDown: false, otherModifiersDown: false) == nil)
    }

    @Test("right Shift and Command/Control/Option chords remain blocked even if their modifier is released first")
    func forbiddenModifiers() {
        for modifierFirst in [false, true] {
            var gesture = FunctionKeyGesture()
            _ = gesture.flagsChanged(isFunctionEvent: true, functionDown: true, leftShiftDown: false, otherModifiersDown: modifierFirst)
            _ = gesture.flagsChanged(isFunctionEvent: false, functionDown: true, leftShiftDown: false, otherModifiersDown: true)
            #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false, leftShiftDown: false, otherModifiersDown: false) == nil)
        }
    }

    @Test("synthetic function flags without a physical Fn edge are ignored")
    func flagsAloneDoNotTrigger() {
        var gesture = FunctionKeyGesture()
        _ = gesture.flagsChanged(isFunctionEvent: false, functionDown: true, leftShiftDown: false, otherModifiersDown: false)
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false, leftShiftDown: false, otherModifiersDown: false) == nil)
    }

    @Test("an ordinary key held before Fn suppresses the entire stroke")
    func ordinaryKeyHeldBeforeFunction() {
        var gesture = FunctionKeyGesture()
        _ = gesture.flagsChanged(isFunctionEvent: true, functionDown: true, leftShiftDown: false,
                                 otherModifiersDown: false, ordinaryKeyAlreadyDown: true)
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false,
                                    leftShiftDown: false, otherModifiersDown: false) == nil)
        _ = gesture.flagsChanged(isFunctionEvent: true, functionDown: true,
                                 leftShiftDown: false, otherModifiersDown: false)
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false,
                                    leftShiftDown: false, otherModifiersDown: false) == .dictate)
    }

    @Test("sleep, tap interruption and permission changes invalidate a pending Fn stroke")
    func interruptedStroke() {
        var gesture = FunctionKeyGesture()
        _ = gesture.flagsChanged(isFunctionEvent: true, functionDown: true, leftShiftDown: true, otherModifiersDown: false)
        gesture.reset()
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false, leftShiftDown: false, otherModifiersDown: false) == nil)
        _ = gesture.flagsChanged(isFunctionEvent: true, functionDown: true, leftShiftDown: false, otherModifiersDown: false)
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false, leftShiftDown: false, otherModifiersDown: false) == .dictate)
    }

    @Test("bare Fn finishes translation or a held-key recording without changing mode")
    func mainKeyFinishesAnySession() {
        var interaction = ShortcutInteraction(mode: .hold)
        #expect(interaction.keyPressed(phase: .idle, trigger: "translation", activation: .toggle) == .start)
        #expect(interaction.keyReleased(phase: .recording, trigger: "translation") == .none)
        #expect(interaction.keyPressed(phase: .recording, trigger: "function", activation: .toggle) == .stop)
        #expect(interaction.keyReleased(phase: .processing, trigger: "function") == .none)
        interaction.reset()
        #expect(interaction.keyPressed(phase: .idle, trigger: "held") == .start)
        #expect(interaction.keyPressed(phase: .recording, trigger: "function", activation: .toggle) == .stop)
        #expect(interaction.keyReleased(phase: .processing, trigger: "held") == .none)
    }

    @Test("releasing a second binding never ends a recording owned by a held shortcut")
    func releaseOwnership() {
        var interaction = ShortcutInteraction(mode: .hold)
        #expect(interaction.keyPressed(phase: .idle, trigger: "first") == .start)
        #expect(interaction.keyPressed(phase: .recording, trigger: "second") == .none)
        #expect(interaction.keyReleased(phase: .recording, trigger: "second") == .none)
        #expect(interaction.isHolding)
        #expect(interaction.keyReleased(phase: .recording, trigger: "first") == .stop)
    }

    @Test("bindings validate safe combinations, compare physical keys and preserve intent on disk")
    func bindingValidationAndRoundTrip() throws {
        let original = ShortcutBinding(keyCode: 49, modifiers: [.control, .option], keyLabel: "Space", intent: .dictate)
        try original.validate()
        let conflict = ShortcutBinding(keyCode: 49, modifiers: [.control, .option], keyLabel: "空格", intent: .translate)
        #expect(original.matches(conflict))
        #expect(try JSONDecoder().decode(ShortcutBinding.self, from: JSONEncoder().encode(original)) == original)
        for binding in [
            ShortcutBinding(keyCode: 0, modifiers: [], keyLabel: "A", intent: .dictate),
            ShortcutBinding(keyCode: 0, modifiers: [.shift], keyLabel: "A", intent: .dictate),
            ShortcutBinding(keyCode: 12, modifiers: [.command], keyLabel: "Q", intent: .dictate),
            ShortcutBinding(keyCode: 53, modifiers: [.control], keyLabel: "Esc", intent: .dictate),
            ShortcutBinding(keyCode: 63, modifiers: [.control], keyLabel: "Fn", intent: .dictate),
            ShortcutBinding(keyCode: 0, modifiers: .init(rawValue: 1000), keyLabel: "A", intent: .dictate)
        ] { #expect(throws: PithError.self) { try binding.validate() } }
    }

    @Test("legacy shortcut preferences remain decodable and retain their physical mapping")
    func legacyShortcuts() throws {
        for shortcut in DictationShortcut.allCases {
            #expect(try JSONDecoder().decode(DictationShortcut.self, from: JSONEncoder().encode(shortcut)) == shortcut)
            if let binding = ShortcutBinding.preset(shortcut) { try binding.validate(); #expect(binding.keyCode == 49) }
        }
        #expect(ShortcutBinding.preset(.function) == nil)
        try ShortcutBinding.translationFallback.validate()
    }
}
