import Testing
@testable import PetKit

@Test func pettingProducesSoothedFaceAndFastRightBiasedWag() {
    let targets = PetExpression.targets(
        needs: PetNeeds(energy: 80, fun: 90, affection: 80),
        activity: .pet,
        engaged: true,
        running: false
    )
    #expect(targets.mood == .content)
    #expect(targets.eyes == .closed)
    #expect(targets.mouthOpenDegrees == 12)
    #expect(targets.tongueOut == 0.2)
    #expect(targets.wagAmplitudeDegrees == 22)
    #expect(targets.wagFrequencyHz == 3.5)
    #expect(targets.wagBiasDegrees > 0)
}

@Test func runningUsesExcitedPantWithoutSocialWag() {
    let targets = PetExpression.targets(
        needs: PetNeeds(energy: 80, fun: 90, affection: 70),
        activity: .idle,
        engaged: false,
        running: true
    )
    #expect(targets.mood == .excited)
    #expect(targets.mouthOpenDegrees == 8)
    #expect(targets.tongueOut == 0.3)
    #expect(targets.wagAmplitudeDegrees == 8, "running tail is a rudder, not a social signal")
}

@Test func fetchStaysExcitedEvenWhenNeedsAreLow() {
    let targets = PetExpression.targets(
        needs: PetNeeds(hunger: 90, energy: 20, fun: 20),
        activity: .fetch,
        engaged: true,
        running: false
    )
    #expect(targets.mood == .excited)
    #expect(targets.wagAmplitudeDegrees == 24)
    #expect(targets.tongueOut == 0.3)
}

@Test func criticalNeedsLowerTailAndSuppressPanting() {
    let targets = PetExpression.targets(
        needs: PetNeeds(hunger: 90, thirst: 20, energy: 20, fun: 25, affection: 40),
        activity: .idle,
        engaged: false,
        running: false
    )
    #expect(targets.mood == .low)
    #expect(targets.tailPitchDegrees > 0)
    #expect(targets.wagFrequencyHz < 1)
    #expect(targets.mouthOpenDegrees == 0)
    #expect(targets.eyes == .squint)
}

@Test func sleepClosesEyesAndStopsExpressionLayers() {
    let targets = PetExpression.targets(
        needs: PetNeeds(),
        activity: .sleep,
        engaged: false,
        running: false
    )
    #expect(targets.mood == .asleep)
    #expect(targets.eyes == .closed)
    #expect(targets.wagAmplitudeDegrees == 0)
    #expect(targets.mouthOpenDegrees == 0)
    #expect(targets.tongueOut == 0)
}

@Test func lastingAffectionDoesNotForcePermanentHighRatePanting() {
    let targets = PetExpression.targets(
        needs: PetNeeds(affection: 90),
        activity: .idle,
        engaged: false,
        running: false
    )
    #expect(targets.mood == .content)
    #expect(targets.wagFrequencyHz < 2)
    #expect(targets.mouthOpenDegrees == 0)
    #expect(targets.tongueOut == 0)
}

@Test func recentPositiveEngagementProducesAHighRateBurst() {
    let targets = PetExpression.targets(
        needs: PetNeeds(affection: 90),
        activity: .idle,
        engaged: true,
        running: false
    )
    #expect(targets.mood == .excited)
    #expect(targets.wagFrequencyHz == 4)
    #expect(targets.tongueOut == 0.3)
}

@Test func attentionRaisesCalmWagWithoutStartingPanting() {
    let needs = PetNeeds(energy: 50, fun: 50, affection: 50)
    let idle = PetExpression.targets(
        needs: needs,
        activity: .idle,
        engaged: false,
        running: false
    )
    let attentive = PetExpression.targets(
        needs: needs,
        activity: .idle,
        engaged: true,
        running: false
    )
    #expect(idle.mood == .calm)
    #expect(idle.wagAmplitudeDegrees == 3.6)
    #expect(attentive.wagAmplitudeDegrees == 6)
    #expect(attentive.tongueOut == 0)
}

@Test func alertCallHoldsTailStillAndEyesWide() {
    let targets = PetExpression.targets(
        needs: PetNeeds(),
        activity: .call,
        engaged: true,
        running: false
    )
    #expect(targets.mood == .alert)
    #expect(targets.eyes == .wide)
    #expect(targets.wagAmplitudeDegrees == 0)
    #expect(targets.tailPitchDegrees < 0)
}
