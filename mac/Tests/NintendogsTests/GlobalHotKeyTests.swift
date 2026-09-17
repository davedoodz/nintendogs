import Testing
@testable import Nintendogs

/// A live Carbon registration is process-wide state, so these run serially.
@Suite(.serialized)
@MainActor
struct GlobalHotKeyTests {
    /// The registration is the whole point of the type: if the key code or
    /// modifier mask were wrong, or the shared event handler failed to install,
    /// `whistle()` would hand back a key that never fires.
    @Test func whistleClaimsTheCombinationExclusivelyAndReleasesIt() {
        let key = GlobalHotKey.whistle {}
        #expect(key != nil)

        // Proves the claim reached the window server rather than no-opping: a
        // second claim on a combination already held must be refused.
        let duplicate = GlobalHotKey.whistle {}
        #expect(duplicate == nil)
        duplicate?.invalidate()

        key?.invalidate()

        // A dropped-but-still-registered key would leave ⌥W permanently dead
        // for every app until reboot, so releasing must actually free it.
        let reclaimed = GlobalHotKey.whistle {}
        #expect(reclaimed != nil)
        reclaimed?.invalidate()
    }

    @Test func invalidateIsIdempotent() {
        let key = GlobalHotKey.whistle {}
        key?.invalidate()
        key?.invalidate()

        let reclaimed = GlobalHotKey.whistle {}
        #expect(reclaimed != nil)
        reclaimed?.invalidate()
    }
}
