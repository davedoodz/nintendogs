import Foundation
import PetKit
import Testing
@testable import Nintendogs

@Test func pettingResumePreservesPriorInteractionWithoutReplayingIt() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    var previous = PetBehavior(state: PetState(
        needs: PetNeeds(hunger: 100, thirst: 20, energy: 80, fun: 70, cleanliness: 80, affection: 60),
        activity: .idle,
        lastUpdated: start
    ))
    previous.interact(.eat, at: start)
    previous.tick(at: start.addingTimeInterval(2))

    var current = previous
    current.interact(.pet, at: start.addingTimeInterval(2))
    current.tick(at: start.addingTimeInterval(3))

    var restored = AppDelegate.restoreBehavior(beforePetting: previous, afterPetting: current)
    #expect(restored.state.activity == .eat)
    #expect(restored.isInteracting)
    #expect(restored.state.needs == current.state.needs)

    restored.tick(at: start.addingTimeInterval(10))
    #expect(!restored.isInteracting, "the original meal deadline must not restart after petting")
}
