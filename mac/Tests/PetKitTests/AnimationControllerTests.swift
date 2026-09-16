import Testing
import SceneKit
@testable import PetKit

@MainActor
private func controllerForShiba() throws -> AnimationController {
    let url = try #require(AssetLocator.shibaModel())
    let model = try ModelLoader.load(url, targetHeight: 1)
    return try AnimationController(root: model.node)
}

@Test func authoredClipCatalogIncludesStoryboardTier() {
    #expect(AnimationController.clipNames.count == 34)
    #expect(AnimationController.clipNames.contains("shiba_pet_head_loop"))
    #expect(AnimationController.clipNames.contains("shiba_paws_up_loop"))
}

@Test @MainActor func repeatedSleepRequestsDoNotRestartThePostureRoute() throws {
    let controller = try controllerForShiba()
    for _ in 0..<240 {
        controller.play(.sleep)
        controller.update(deltaTime: 1.0 / 30)
    }
    #expect(controller.currentClip == "shiba_sleep_loop")
}

@Test @MainActor func cancelledWalkDoesNotResumeAfterStandingUp() throws {
    let controller = try controllerForShiba()
    controller.play(.idle, careRequest: true)
    for _ in 0..<120 { controller.update(deltaTime: 1.0 / 30) }
    #expect(controller.startLocomotion(.walk))
    controller.update(deltaTime: 0.2)
    controller.endLocomotion()
    for _ in 0..<150 {
        controller.update(deltaTime: 1.0 / 30)
        #expect(controller.currentClip != "shiba_walk_loop")
    }
    #expect(controller.currentClip == "shiba_beg_loop")
}

@Test @MainActor func playStaysAnimatedUntilCareStateChanges() throws {
    let controller = try controllerForShiba()
    controller.play(.play)
    for _ in 0..<300 { controller.update(deltaTime: 1.0 / 30) }
    #expect(controller.currentClip == "shiba_happy")
    #expect(controller.isAnimating)
    controller.play(.eat)
    for _ in 0..<120 { controller.update(deltaTime: 1.0 / 30) }
    #expect(controller.currentClip == "shiba_eat_loop")
}

@Test @MainActor func pettingChoreographyHandsReactionIntoHeadLoop() throws {
    let controller = try controllerForShiba()
    try controller.playChoreography(["shiba_pet_react", "shiba_pet_head_loop"])
    for _ in 0..<90 { controller.update(deltaTime: 1.0 / 30) }
    #expect(controller.currentClip == "shiba_pet_head_loop")
    #expect(controller.isAnimating)
}

@Test @MainActor func callChoreographyPreservesAuthoredPoseChain() throws {
    let controller = try controllerForShiba()
    try controller.playChoreography(["shiba_call_stun", "shiba_call_curious"])
    for _ in 0..<70 { controller.update(deltaTime: 1.0 / 30) }
    #expect(controller.currentClip == "shiba_call_curious")
    #expect(!controller.isAnimating)

    try controller.playChoreography(["shiba_run_loop"])
    #expect(controller.currentClip == "shiba_run_loop")

    try controller.playChoreography(["shiba_paws_up_enter", "shiba_paws_up_loop"])
    for _ in 0..<40 { controller.update(deltaTime: 1.0 / 30) }
    #expect(controller.currentClip == "shiba_paws_up_loop")

    try controller.playChoreography(["shiba_paws_down", "shiba_sit_idle_loop"])
    for _ in 0..<40 { controller.update(deltaTime: 1.0 / 30) }
    #expect(controller.currentClip == "shiba_sit_idle_loop")
}

@Test @MainActor func mealCancelsAnUnstartedGreeting() throws {
    let controller = try controllerForShiba()
    let director = AmbientDirector(controller: controller, seed: 1)
    director.greet()
    controller.play(.eat)
    director.update(deltaTime: 0.1, needs: PetNeeds(), activity: .eat, careRequest: false, suppressed: true)
    controller.play(.idle)
    for _ in 0..<60 {
        director.update(deltaTime: 1.0 / 30, needs: PetNeeds(), activity: .idle, careRequest: false, suppressed: false)
        controller.update(deltaTime: 1.0 / 30)
        #expect(controller.currentClip == "shiba_idle_loop")
    }
}
