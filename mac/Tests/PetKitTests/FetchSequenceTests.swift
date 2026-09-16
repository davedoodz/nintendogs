import Testing
import Foundation
@testable import PetKit

private let clips = FetchSequence.ClipDurations(pickup: 0.5, happy: 0.75)

/// Runs `sequence` forward in 1/60 s ticks until `until` holds or the budget runs out,
/// mirroring how the app's loop drives it.
private func run(
    _ sequence: inout FetchSequence,
    seconds budget: TimeInterval = 20,
    tick: TimeInterval = 1.0 / 60,
    step: ((inout FetchSequence) -> Void)? = nil,
    until: (FetchSequence) -> Bool
) -> Bool {
    var elapsed: TimeInterval = 0
    while elapsed < budget {
        if until(sequence) { return true }
        step?(&sequence)
        sequence.advance(by: tick)
        elapsed += tick
    }
    return until(sequence)
}

@Test func theDogRunsAtTheBallFromTheThrowAndPicksItUpOnceItRests() {
    var sequence = FetchSequence(
        home: SIMD2(0, 0), ball: SIMD2(0, -4), returnTo: SIMD2(0, 0), clipDurations: clips
    )
    #expect(sequence.phase == .chase, "the chase starts at the throw, not at the landing")
    #expect(sequence.clip == "shiba_run_loop")

    // Ball still bouncing: the dog reaches it and waits rather than mouthing a moving ball.
    let reached = run(&sequence, step: { $0.updateBall(position: SIMD2(0, -4), atRest: false) }) {
        $0.phase == .watch
    }
    #expect(reached)
    #expect(sequence.clip == "shiba_alert")
    #expect(abs(sequence.position.y - -4) <= FetchSequence.pickupRadius + 1e-6)

    sequence.updateBall(position: SIMD2(0, -4), atRest: true)
    sequence.advance(by: 1.0 / 60)
    #expect(sequence.phase == .pickup)
    #expect(sequence.clip == "shiba_fetch_pickup")
}

@Test func theChaseFollowsTheBallToWhereItActuallyStops() {
    var sequence = FetchSequence(
        home: SIMD2(0, 0), ball: SIMD2(0, -3), returnTo: SIMD2(0, 0), clipDurations: clips
    )
    // Predicted rest was -3; the ball bounces on to -5 while the dog is running.
    var moved = false
    let arrived = run(&sequence, step: { sequence in
        if !moved, sequence.position.y < -1 {
            moved = true
            sequence.updateBall(position: SIMD2(1.5, -5), atRest: true)
        }
    }) { $0.phase == .pickup }
    #expect(arrived)
    let offset = sequence.position - SIMD2(1.5, -5)
    #expect((offset.x * offset.x + offset.y * offset.y).squareRoot() <= FetchSequence.pickupRadius + 1e-6)
}

@Test func theBallIsCarriedToTheLatestReturnTargetAndPresentedToTheViewer() {
    var sequence = FetchSequence(
        home: SIMD2(0, 0), ball: SIMD2(0, -3), returnTo: SIMD2(0, 0), clipDurations: clips
    )
    sequence.updateBall(position: SIMD2(0, -3), atRest: true)
    let carrying = run(&sequence) { $0.phase == .carry }
    #expect(carrying)
    #expect(sequence.ballAttached, "the ball travels in the mouth while carrying")

    // The thrower's cursor moved during the trip; the dog ends up at the new spot.
    let target = SIMD2<Double>(-1.2, -0.5)
    let dropped = run(&sequence, step: { $0.updateReturn(to: target) }) { $0.phase == .drop }
    #expect(dropped)
    let miss = sequence.position - target
    #expect((miss.x * miss.x + miss.y * miss.y).squareRoot() <= FetchSequence.arrivalRadius + 1e-6)
    #expect(!sequence.ballAttached, "the ball is on the ground from the drop onward")

    // Toward the camera rather than along the carry heading, so an off-centre cursor cannot
    // fling the ball past the panel edge.
    let offset = sequence.ballPosition - sequence.position
    #expect(abs(offset.x) < 1e-9)
    #expect(abs(offset.y - 0.35) < 1e-9, "the ball is presented between the dog and you")

    // Once dropped, the ball stops tracking a moving cursor.
    let restingBall = sequence.ballPosition
    sequence.updateReturn(to: SIMD2(3, -2))
    sequence.advance(by: 0.1)
    #expect(sequence.ballPosition == restingBall)
}

@Test func theTripEndsFacingTheCameraAndStaysDone() {
    var sequence = FetchSequence(
        home: SIMD2(0, 0), ball: SIMD2(2, -2), returnTo: SIMD2(0, 0), clipDurations: clips
    )
    sequence.updateBall(position: SIMD2(2, -2), atRest: true)
    #expect(run(&sequence) { $0.phase == .done })
    #expect(sequence.clip == nil)
    #expect(abs(sequence.heading) < 0.2, "the dog turns back to the camera to celebrate")

    let resting = sequence.position
    sequence.advance(by: 5)
    #expect(sequence.phase == .done)
    #expect(sequence.position == resting)
}

@Test func aLargeCatchUpStepFollowsTheSamePathAsManySmallOnes() {
    let base = FetchSequence(
        home: SIMD2(0, 0), ball: SIMD2(1, -4), returnTo: SIMD2(0.5, -0.5), clipDurations: clips
    )
    var fine = base
    fine.updateBall(position: SIMD2(1, -4), atRest: true)
    var coarse = fine

    for _ in 0..<360 { fine.advance(by: FetchSequence.step) }
    coarse.advance(by: 360 * FetchSequence.step)

    #expect(fine.phase == coarse.phase)
    let drift = fine.position - coarse.position
    #expect((drift.x * drift.x + drift.y * drift.y).squareRoot() < 1e-9)
}

@Test func nonAdvancingTimeIsIgnored() {
    var sequence = FetchSequence(
        home: SIMD2(0, 0), ball: SIMD2(0, -2), returnTo: SIMD2(0, 0), clipDurations: clips
    )
    let before = sequence
    sequence.advance(by: 0)
    sequence.advance(by: -1)
    sequence.advance(by: .nan)
    #expect(sequence == before)
}

@Test func theEstimatedTripCoversBothLegsAndBothClips() {
    let sequence = FetchSequence(
        home: SIMD2(0, 0), ball: SIMD2(0, -4), returnTo: SIMD2(0, 0), clipDurations: clips
    )
    let expected = 4 / FetchSequence.runSpeed + clips.pickup + FetchSequence.turnDuration
        + 4 / FetchSequence.carrySpeed + FetchSequence.dropDuration + clips.happy
    #expect(abs(sequence.estimatedDuration - expected) < 1e-9)
}
