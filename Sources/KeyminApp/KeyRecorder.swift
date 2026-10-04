import AppKit
import SwiftUI

/// Captures a keypress delivered to Keymin and converts it to skhd syntax.
/// A binding consumed by skhd may leave only modifier events. The recorder uses
/// those as a hint of interception; tapping modifiers alone leaves the same trace.
@MainActor
final class KeyRecorder: ObservableObject {
    /// Why a press did not arrive as a shortcut, shown under the record button.
    enum Notice: Equatable {
        /// Modifiers were held and released, but no key press arrived. Recording continues.
        case intercepted([SkhdModifier])
        /// Another app came to the front while recording, usually because the shortcut launched it.
        /// Recording stops.
        case lostFocus([SkhdModifier])
    }

    @Published private(set) var isRecording = false
    /// The modifiers currently held while recording, shown live in the button.
    @Published private(set) var heldModifiers: [SkhdModifier] = []
    /// The latest explanation; cleared when recording starts again or a modifier goes down.
    @Published var notice: Notice?

    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var onCapture: (([SkhdModifier], SkhdKey) -> Void)?
    /// The largest modifier set seen during the current hold, kept for the notice.
    private var peakModifiers: [SkhdModifier] = []

    // begin(onCapture): Start listening for one key press and report it through the callback.
    // A second call while recording cancels instead, so the record button toggles.
    func begin(onCapture: @escaping ([SkhdModifier], SkhdKey) -> Void) {
        guard !isRecording else {
            cancel()
            return
        }
        // Start clean: no stale notice or held modifiers from the last recording.
        self.onCapture = onCapture
        notice = nil
        heldModifiers = []
        peakModifiers = []
        isRecording = true
        // Local monitors see only this app's events, so no permission is needed.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            let modifiers = Self.modifiers(from: event.modifierFlags)
            // Escape on its own cancels without capturing anything.
            if event.keyCode == 53, modifiers.isEmpty {
                self.cancel()
                return nil
            }
            let key = Self.key(for: event)
            // Finishing clears the callback, so keep it before tearing the monitors down.
            let callback = self.onCapture
            self.finish()
            callback?(modifiers, key)
            return nil
        }
        // Modifier changes feed the live button label and the intercepted-press detection. The
        // event is passed on so the rest of the app still sees it.
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, self.isRecording else { return event }
            self.trackModifiers(Self.modifiers(from: event.modifierFlags))
            return event
        }
        // Losing the active state ends the recording with an explanation. The observer runs on
        // the main queue, so hopping onto the main actor is safe.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRecording else { return }
                let held = self.peakModifiers
                self.finish()
                self.notice = .lostFocus(held)
            }
        }
    }

    // trackModifiers(modifiers): Track held keys and flag a possible intercepted
    // shortcut when modifiers are released without a key-down event.
    private func trackModifiers(_ modifiers: [SkhdModifier]) {
        // Releasing all modifiers after a hold may indicate an intercepted shortcut.
        if modifiers.isEmpty {
            // Ignore empty flag events that were not preceded by a modifier hold.
            if !peakModifiers.isEmpty { notice = .intercepted(peakModifiers) }
            heldModifiers = []
            peakModifiers = []
        } else {
            // Still holding: show the set live and remember the largest one for the notice.
            heldModifiers = modifiers
            // Keep the fullest chord instead of shrinking it during key release.
            if modifiers.count >= peakModifiers.count { peakModifiers = modifiers }
            notice = nil
        }
    }

    // cancel(): Stop recording without capturing anything.
    func cancel() {
        finish()
    }

    // finish(): Remove the monitors and the observer, then reset every piece of recording state,
    // including the capture callback.
    private func finish() {
        // Release each resource only if recording installed it.
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        // Modifier monitoring has its own AppKit token.
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        // Stop observing activation once the recorder no longer owns a callback.
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        keyMonitor = nil
        flagsMonitor = nil
        resignObserver = nil
        isRecording = false
        heldModifiers = []
        peakModifiers = []
        onCapture = nil
    }

    // modifiers(from flags): Read generic skhd modifiers in canonical order. The fn
    // flag is ignored because macOS also sets it for arrow and function keys, which skhd handles
    // with an implicit flag of its own; fn can still be added by hand in the editor.
    static func modifiers(from flags: NSEvent.ModifierFlags) -> [SkhdModifier] {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: [SkhdModifier] = []
        // Record generic families; event flags here do not choose a physical side.
        if flags.contains(.control) { modifiers.append(.ctrl) }
        // macOS Option is named alt in skhd syntax.
        if flags.contains(.option) { modifiers.append(.alt) }
        // Keep Shift explicit rather than encoding it in the key character.
        if flags.contains(.shift) { modifiers.append(.shift) }
        // Command is the last supported family in canonical order.
        if flags.contains(.command) { modifiers.append(.cmd) }
        return modifiers
    }

    // key(for event): Read keywords, then layout characters, then
    // raw key codes, matching how people write skhd configurations by hand.
    static func key(for event: NSEvent) -> SkhdKey {
        let code = UInt32(event.keyCode)
        // Keys with a keyword, such as return or f1.
        if let literal = SkhdLiteralKey.byKeyCode[code] { return .literal(literal.keyword) }
        // Letter and digit keys use the character the layout produced, so the binding follows
        // the layout like a hand-written one would.
        if SkhdKeyCodes.characters[code] != nil,
           let typed = event.charactersIgnoringModifiers, typed.count == 1,
           let character = typed.lowercased().first, character.isASCII, character.isLetter || character.isNumber {
            return .character(character)
        }
        return .code(code)
    }
}
