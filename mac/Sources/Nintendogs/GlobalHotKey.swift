import AppKit
import Carbon.HIToolbox

/// A system-wide key combination, registered through the Carbon hot-key API.
///
/// This app is an accessory with a non-activating panel, so `keyDown` never
/// reaches it (see `HeldItemOverlay`) and it has no main menu whose key
/// equivalents could fire while another app is focused.
/// `NSEvent.addGlobalMonitorForEvents` would see the key but requires the user
/// to grant Input Monitoring in System Settings. `RegisterEventHotKey` needs no
/// permission at all, which is why it is used here.
///
/// The owner MUST hold the returned instance for as long as the key should work
/// and call `invalidate()` when done: the Carbon registration outlives a dropped
/// reference, so a discarded instance would leave a dead key registered.
@MainActor
final class GlobalHotKey {
    /// The dog's whistle key. Defined here so no caller has to import Carbon
    /// just to name one key code, and so the registration and the label the
    /// user reads can never drift apart.
    ///
    /// ⌥W rather than a bare `W`: a modifier-free registration is possible
    /// and deliberately unused, because it would take that key away from every
    /// other app.
    static let whistleDisplayName = "⌥W"

    static func whistle(action: @MainActor @escaping () -> Void) -> GlobalHotKey? {
        GlobalHotKey(keyCode: kVK_ANSI_W, modifiers: optionKey, action: action)
    }

    /// Carbon passes the callback only a numeric id, never a context pointer,
    /// so the actions are looked up here. Storing the closure rather than the
    /// instance keeps this table from retaining its owner.
    private static var actions: [UInt32: @MainActor () -> Void] = [:]
    private static var nextIdentifier: UInt32 = 1
    private static var handler: EventHandlerRef?

    private let identifier: UInt32
    private var reference: EventHotKeyRef?

    /// - Parameters:
    ///   - keyCode: a virtual key code, e.g. `kVK_ANSI_W`. Layout-independent:
    ///     this is a physical key, not the character it produces.
    ///   - modifiers: Carbon modifier mask, e.g. `cmdKey | optionKey`. Registering
    ///     with no modifiers would take the bare key away from every other app.
    /// - Returns: `nil` when the combination is already claimed by the system or
    ///   another app, so the caller can report that instead of silently having
    ///   a key that does nothing.
    init?(keyCode: Int, modifiers: Int, action: @MainActor @escaping () -> Void) {
        guard Self.installHandler() else { return nil }
        identifier = Self.nextIdentifier
        Self.nextIdentifier += 1

        // Signature is a debugging tag in Carbon's registry, not an identifier
        // this app resolves; the per-key `id` is what the callback matches on.
        let hotKeyID = EventHotKeyID(signature: OSType(0x53484942), id: identifier)
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, reference != nil else { return nil }
        Self.actions[identifier] = action
    }

    func invalidate() {
        Self.actions[identifier] = nil
        guard let reference else { return }
        UnregisterEventHotKey(reference)
        self.reference = nil
    }

    /// One process-wide handler serves every registered key; Carbon delivers the
    /// event on the main run loop, which is what makes the main-actor hop safe.
    private static func installHandler() -> Bool {
        guard handler == nil else { return true }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let read = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard read == noErr else { return read }
                return MainActor.assumeIsolated {
                    guard let action = GlobalHotKey.actions[hotKeyID.id] else {
                        return OSStatus(eventNotHandledErr)
                    }
                    action()
                    return noErr
                }
            },
            1,
            &spec,
            nil,
            &handler
        )
        return status == noErr
    }
}
