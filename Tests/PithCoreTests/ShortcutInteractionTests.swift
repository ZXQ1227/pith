import Testing
@testable import PithCore

@Suite("Shortcut interaction")
struct ShortcutInteractionTests {
    @Test("toggle starts once and stops on the next distinct press")
    func toggleUsesDistinctPresses() {
        var interaction = ShortcutInteraction(mode: .toggle)
        #expect(interaction.keyPressed(phase: .idle) == .start)
        #expect(interaction.keyPressed(phase: .recording) == .none)
        #expect(interaction.keyReleased(phase: .recording) == .none)
        #expect(interaction.keyPressed(phase: .recording) == .stop)
        #expect(!interaction.ownsSession)
    }

    @Test("toggle can stop recording started from the menu")
    func toggleCanStopMenuRecording() {
        var interaction = ShortcutInteraction(mode: .toggle)
        #expect(interaction.keyPressed(phase: .recording) == .stop)
        #expect(interaction.keyReleased(phase: .processing) == .none)
    }

    @Test("hold release stops only the recording started by its own press")
    func holdOwnsItsRecording() {
        var interaction = ShortcutInteraction(mode: .hold)
        #expect(interaction.keyPressed(phase: .idle) == .start)
        #expect(interaction.keyPressed(phase: .recording) == .none)
        #expect(interaction.keyReleased(phase: .recording) == .stop)
        #expect(interaction.keyReleased(phase: .recording) == .none)
        #expect(!interaction.ownsSession)
    }

    @Test("unmatched releases and menu recordings are unaffected by hold events")
    func holdDoesNotStopAnotherSession() {
        var interaction = ShortcutInteraction(mode: .hold)
        #expect(interaction.keyReleased(phase: .recording) == .none)
        #expect(interaction.keyPressed(phase: .recording) == .none)
        #expect(interaction.keyReleased(phase: .recording) == .none)
    }

    @Test("releasing hold while the permission dialog is open cancels startup")
    func holdReleaseCancelsPermissionRequest() {
        var interaction = ShortcutInteraction(mode: .hold)
        #expect(interaction.keyPressed(phase: .idle) == .start)
        #expect(interaction.keyReleased(phase: .requestingPermission) == .cancel)
        #expect(!interaction.ownsSession)
        #expect(interaction.keyReleased(phase: .recording) == .none)
    }

    @Test("a second toggle press can cancel its pending microphone request")
    func toggleCanCancelPermissionRequest() {
        var interaction = ShortcutInteraction(mode: .toggle)
        #expect(interaction.keyPressed(phase: .idle) == .start)
        #expect(interaction.keyReleased(phase: .requestingPermission) == .none)
        #expect(interaction.keyPressed(phase: .requestingPermission) == .cancel)
    }

    @Test("processing and insertion never start a concurrent recording")
    func processingIgnoresShortcuts() {
        for mode in ShortcutActivationMode.allCases {
            for phase in [SessionPhase.processing, .inserting] {
                var interaction = ShortcutInteraction(mode: mode)
                #expect(interaction.keyPressed(phase: phase) == .none)
                #expect(interaction.keyReleased(phase: phase) == .none)
            }
        }
    }

    @Test("cancel or failure clears ownership before another recording begins")
    func resetDropsOldSessionOwnership() {
        var interaction = ShortcutInteraction(mode: .hold)
        #expect(interaction.keyPressed(phase: .idle) == .start)
        interaction.reset()
        #expect(interaction.keyReleased(phase: .recording) == .none)
        #expect(interaction.keyPressed(phase: .failed("Microphone unavailable")) == .start)
    }

    @Test("changing mode clears any pending shortcut press")
    func modeChangeResetsInteraction() {
        var interaction = ShortcutInteraction(mode: .hold)
        #expect(interaction.keyPressed(phase: .idle) == .start)
        interaction.mode = .toggle
        #expect(!interaction.isPressed)
        #expect(!interaction.ownsSession)
        #expect(interaction.keyReleased(phase: .recording) == .none)
    }
}
