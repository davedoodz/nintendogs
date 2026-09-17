import AppKit
import Testing
@testable import Nintendogs

@Test @MainActor func petPanelCannotBeMovedByDraggingItsBackground() {
    let panel = PetPanel()
    defer { panel.close() }

    #expect(panel.isMovableByWindowBackground == false)
}

@Test func pettingRangeIncludesBoundaryButRejectsBeyondIt() {
    let center = CGPoint(x: 40, y: 30)

    #expect(SceneHost.isWithinPettingRange(CGPoint(x: 58, y: 30), center: center, radius: 18))
    #expect(!SceneHost.isWithinPettingRange(CGPoint(x: 58.01, y: 30), center: center, radius: 18))
}

@Test func pettingCursorClosesItsHandWhileHeadPressIsHeld() {
    #expect(
        SceneHost.pettingCursorAppearance(enabled: true, overHead: true, isPetting: false)
            == .openHand
    )
    #expect(
        SceneHost.pettingCursorAppearance(enabled: true, overHead: true, isPetting: true)
            == .closedHand
    )
    #expect(
        SceneHost.pettingCursorAppearance(enabled: true, overHead: false, isPetting: true)
            == .arrow
    )
}
