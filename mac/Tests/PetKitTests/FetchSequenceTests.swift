import Testing
import Foundation
@testable import PetKit

private let epsilon = 1e-6

@Test func phasesRunInOrderWithMatchingClipsForAFourUnitThrow() {
    let home = SIMD2<Double>(0, 0)
    let ball = SIMD2<Double>(0, 4)
    let clips = FetchSequence.ClipDurations(pickup: 0.5, happy: 0.75)
    let runDuration = 4.0 / FetchSequence.runSpeed
    let carryDuration = 4.0 / FetchSequence.carrySpeed
    let expectedTotal = FetchSequence.turnDuration + runDuration + clips.pickup
        + FetchSequence.turnDuration + carryDuration + FetchSequence.dropDuration + clips.happy

    let base = FetchSequence(home: home, ball: ball, clipDurations: clips)
    #expect(abs(base.totalDuration - expectedTotal) < 1e-9)
    #expect(base.phase == .turnToBall)
    #expect(base.clip == "shiba_run_loop")

    let boundaries: [(phase: FetchSequence.Phase, clip: String?, at: TimeInterval)] = [
        (.run, "shiba_run_loop", FetchSequence.turnDuration),
        (.pickup, "shiba_fetch_pickup", FetchSequence.turnDuration + runDuration),
        (.turnHome, "shiba_fetch_carry_loop", FetchSequence.turnDuration + runDuration + clips.pickup),
        (.carry, "shiba_fetch_carry_loop", 2 * FetchSequence.turnDuration + runDuration + clips.pickup),
        (.drop, "shiba_fetch_carry_loop", 2 * FetchSequence.turnDuration + runDuration + clips.pickup + carryDuration),
        (.celebrate, "shiba_happy", 2 * FetchSequence.turnDuration + runDuration + clips.pickup + carryDuration + FetchSequence.dropDuration),
        (.done, nil, expectedTotal),
    ]

    for (expectedPhase, expectedClip, boundary) in boundaries {
        var before = base
        before.advance(by: boundary - epsilon)
        #expect(before.phase != expectedPhase, "still mid-phase just before \(boundary)s")

        var after = base
        after.advance(by: boundary + epsilon)
        #expect(after.phase == expectedPhase, "phase should be \(expectedPhase) just after \(boundary)s")
        #expect(after.clip == expectedClip)
    }
}

@Test func positionAndHeadingSettleAtHomeAndCameraWhenDone() {
    let home = SIMD2<Double>(1, 2)
    let ball = SIMD2<Double>(-3, 6)
    let sequence0 = FetchSequence(home: home, ball: ball, clipDurations: .init(pickup: 0.3, happy: 0.4))
    var sequence = sequence0
    let total = sequence0.totalDuration
    sequence.advance(by: total + 5) // overshoot; extra time is discarded, not carried past `done`
    #expect(sequence.phase == .done)
    #expect(sequence.position == home)
    #expect(sequence.heading == 0)
    #expect(sequence.clip == nil)
    #expect(sequence.ballAttached == false)
    #expect(sequence.ballPosition == home + SIMD2<Double>(0.35, 0.3))
}

@Test func headingFacesTheBallWhileRunningAndTheCameraWhileCelebrating() {
    let home = SIMD2<Double>(0, 0)
    let ball = SIMD2<Double>(3, 0) // straight along +x -> heading atan2(3, 0) == pi/2
    let clips = FetchSequence.ClipDurations(pickup: 0.2, happy: 0.3)
    let base = FetchSequence(home: home, ball: ball, clipDurations: clips)

    var duringRun = base
    duringRun.advance(by: FetchSequence.turnDuration + 0.05)
    #expect(duringRun.phase == .run)
    #expect(abs(duringRun.heading - .pi / 2) < 1e-9, "heading should face the ball while running")

    var duringCelebrate = base
    duringCelebrate.advance(by: base.totalDuration - 0.05)
    #expect(duringCelebrate.phase == .celebrate)
    #expect(duringCelebrate.heading == 0, "heading should face the camera while celebrating")
}

@Test func ballAttachedOnlyFromTurnHomeThroughCarry() {
    let home = SIMD2<Double>(0, 0)
    let ball = SIMD2<Double>(2, 0)
    let clips = FetchSequence.ClipDurations(pickup: 0.4, happy: 0.5)
    let base = FetchSequence(home: home, ball: ball, clipDurations: clips)
    let runDuration = 2.0 / FetchSequence.runSpeed
    let carryDuration = 2.0 / FetchSequence.carrySpeed

    var duringPickup = base
    duringPickup.advance(by: FetchSequence.turnDuration + runDuration + 0.1)
    #expect(duringPickup.phase == .pickup)
    #expect(duringPickup.ballAttached == false)

    let toPickupEnd = FetchSequence.turnDuration + runDuration + clips.pickup
    var duringTurnHome = base
    duringTurnHome.advance(by: toPickupEnd + 0.01)
    #expect(duringTurnHome.phase == .turnHome)
    #expect(duringTurnHome.ballAttached == true)

    let toCarryStart = toPickupEnd + FetchSequence.turnDuration
    var duringCarry = base
    duringCarry.advance(by: toCarryStart + 0.1)
    #expect(duringCarry.phase == .carry)
    #expect(duringCarry.ballAttached == true)

    var duringDrop = base
    duringDrop.advance(by: toCarryStart + carryDuration + 0.01)
    #expect(duringDrop.phase == .drop)
    #expect(duringDrop.ballAttached == false)
}

@Test func ballPositionTracksLandingSpotThenTheDogThenTheDropSpot() {
    let home = SIMD2<Double>(0, 0)
    let ball = SIMD2<Double>(2, 0)
    let clips = FetchSequence.ClipDurations(pickup: 0.4, happy: 0.5)
    let base = FetchSequence(home: home, ball: ball, clipDurations: clips)
    let runDuration = 2.0 / FetchSequence.runSpeed

    var duringRun = base
    duringRun.advance(by: FetchSequence.turnDuration + 0.1)
    #expect(duringRun.phase == .run)
    #expect(duringRun.ballPosition == ball, "ball waits at the landing spot until picked up")

    let toCarryStart = 2 * FetchSequence.turnDuration + runDuration + clips.pickup
    var duringCarry = base
    duringCarry.advance(by: toCarryStart + 0.1)
    #expect(duringCarry.phase == .carry)
    #expect(duringCarry.ballPosition == duringCarry.position, "ball follows the dog while attached")

    var afterDrop = base
    afterDrop.advance(by: base.totalDuration - clips.happy - 0.01)
    #expect(afterDrop.phase == .drop)
    #expect(afterDrop.ballPosition == home + SIMD2<Double>(0.35, 0.3))
}

@Test func aLargeAdvanceInOneCallCrossesSeveralPhases() {
    let home = SIMD2<Double>(0, 0)
    let ball = SIMD2<Double>(1, 0)
    var sequence = FetchSequence(home: home, ball: ball, clipDurations: .init(pickup: 0.1, happy: 0.1))
    #expect(sequence.phase == .turnToBall)
    sequence.advance(by: sequence.totalDuration) // one catch-up step covering all 7 timed phases
    #expect(sequence.phase == .done)
    #expect(sequence.position == home)
}

@Test func nonPositiveOrNonFiniteAdvanceIsANoOp() {
    let home = SIMD2<Double>(0, 0)
    let ball = SIMD2<Double>(2, 0)
    var sequence = FetchSequence(home: home, ball: ball, clipDurations: .init(pickup: 0.2, happy: 0.2))
    sequence.advance(by: 0.1)
    let snapshot = sequence
    sequence.advance(by: 0)
    sequence.advance(by: -1)
    sequence.advance(by: .nan)
    sequence.advance(by: .infinity)
    #expect(sequence == snapshot)
}

@Test func zeroDistanceThrowNeverProducesANonFiniteHeading() {
    let spot = SIMD2<Double>(1, 1)
    let clips = FetchSequence.ClipDurations(pickup: 0.2, happy: 0.2)
    var sequence = FetchSequence(home: spot, ball: spot, clipDurations: clips)
    var iterations = 0
    while sequence.phase != .done, iterations < 1000 {
        sequence.advance(by: 0.05)
        #expect(sequence.heading.isFinite)
        #expect(sequence.heading == 0, "coincident home/ball has no direction, so heading stays facing the camera")
        #expect(sequence.position == spot)
        iterations += 1
    }
    #expect(sequence.phase == .done)
}
