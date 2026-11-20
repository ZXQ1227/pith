import Testing
@testable import PithCore

@Suite("Fn hold hint")
struct FunctionHoldHintTests {
    @Test("long bare Fn shows help and release does not dictate")
    func holdIsNotTap() {
        var gesture = FunctionKeyGesture()
        #expect(gesture.revealHint() == false)
        _ = gesture.flagsChanged(isFunctionEvent: true, functionDown: true,
                                 leftShiftDown: false, otherModifiersDown: false)
        #expect(gesture.revealHint() == true)
        #expect(gesture.isHintVisible)
        #expect(gesture.revealHint() == false)
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false,
                                    leftShiftDown: false, otherModifiersDown: false) == nil)
        #expect(!gesture.isHintVisible)
        _ = gesture.flagsChanged(isFunctionEvent: true, functionDown: true,
                                 leftShiftDown: false, otherModifiersDown: false)
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false,
                                    leftShiftDown: false, otherModifiersDown: false) == .dictate)
    }

    @Test("a chord can be chosen while help is visible", arguments: [ShortcutIntent.translate, .ask])
    func chooseChord(intent: ShortcutIntent) {
        var gesture = FunctionKeyGesture()
        _ = gesture.flagsChanged(isFunctionEvent: true, functionDown: true,
                                 leftShiftDown: false, otherModifiersDown: false)
        #expect(gesture.revealHint() == true)
        if intent == .translate {
            _ = gesture.flagsChanged(isFunctionEvent: false, functionDown: true,
                                     leftShiftDown: true, otherModifiersDown: false)
        } else { #expect(gesture.spacePressed() == true) }
        #expect(!gesture.isHintVisible)
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false,
                                    leftShiftDown: false, otherModifiersDown: false) == intent)
    }

    @Test("typing and interruptions dismiss help without firing a gesture")
    func dismissHelp() {
        var gesture = FunctionKeyGesture()
        _ = gesture.flagsChanged(isFunctionEvent: true, functionDown: true,
                                 leftShiftDown: false, otherModifiersDown: false)
        #expect(gesture.revealHint() == true)
        gesture.ordinaryKeyPressed()
        #expect(!gesture.isHintVisible)
        #expect(gesture.flagsChanged(isFunctionEvent: true, functionDown: false,
                                    leftShiftDown: false, otherModifiersDown: false) == nil)
        _ = gesture.flagsChanged(isFunctionEvent: true, functionDown: true,
                                 leftShiftDown: false, otherModifiersDown: false)
        #expect(gesture.revealHint() == true)
        gesture.reset()
        #expect(!gesture.isHintVisible)
        #expect(!gesture.canRevealHint)
    }
}
