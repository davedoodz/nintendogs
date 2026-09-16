import Testing
import Foundation
@testable import PetKit

private let bounds = BallFlight.Bounds(xLimit: 6, zNear: 0.6, zFar: -8)
private let launch = SIMD3<Double>(0, 0.9, 1.6)

/// Advances a flight in 1/60 s ticks — the app's loop cadence — until it rests.
private func settle(_ flight: inout BallFlight, seconds budget: TimeInterval = 10) {
    var elapsed: TimeInterval = 0
    while !flight.isAtRest, elapsed < budget {
        flight.advance(by: 1.0 / 60)
        elapsed += 1.0 / 60
    }
}

@Test func theFirstImpactIsTheAimedSpot() {
    let aim = SIMD2<Double>(1.5, -4)
    var flight = BallFlight(launch: launch, aim: aim, bounds: bounds)
    var previous = flight
    while flight.bounceCount == 0, !flight.isRolling, !flight.isAtRest {
        previous = flight
        flight.advance(by: BallFlight.step)
    }
    // `previous` is the last airborne sample; the impact is resolved on the next substep.
    #expect(previous.height >= BallFlight.radius)
    let miss = flight.groundPosition - aim
    #expect((miss.x * miss.x + miss.y * miss.y).squareRoot() < 0.02, "the aim marker must not lie")
}

@Test func thePredictedRestIsWhereTheBallActuallyStops() {
    let flight = BallFlight(launch: launch, aim: SIMD2(-2, -5), bounds: bounds)
    let predicted = flight.predictedRest
    var simulated = flight
    settle(&simulated)
    #expect(simulated.isAtRest)
    let drift = simulated.groundPosition - predicted
    #expect((drift.x * drift.x + drift.y * drift.y).squareRoot() < 1e-9)
}

@Test func theBallBouncesPastTheAimAndThenRollsToRest() {
    let aim = SIMD2<Double>(0, -4)
    var flight = BallFlight(launch: launch, aim: aim, bounds: bounds)
    settle(&flight)
    #expect(flight.isAtRest)
    #expect(flight.bounceCount >= 1, "a tennis ball rebounds at least once")
    #expect(flight.groundPosition.y < aim.y, "bounces and roll carry it beyond the first impact")
    #expect(abs(flight.height - BallFlight.radius) < 1e-9, "it rests on the ground, not in it")
}

@Test func restStaysInsideTheArena() {
    var flight = BallFlight(launch: launch, aim: SIMD2(6, -8), bounds: bounds)
    settle(&flight)
    #expect(flight.isAtRest)
    #expect(flight.groundPosition.x <= bounds.xLimit + 1e-9)
    #expect(flight.groundPosition.y >= bounds.zFar - 1e-9)
}

@Test func slicingTimeDifferentlyDoesNotChangeTheTrajectory() {
    let base = BallFlight(launch: launch, aim: SIMD2(1, -3), bounds: bounds)
    var fine = base
    for _ in 0..<360 { fine.advance(by: BallFlight.step) }
    var coarse = base
    coarse.advance(by: 360 * BallFlight.step)
    let drift = fine.position - coarse.position
    #expect((drift.x * drift.x + drift.y * drift.y + drift.z * drift.z).squareRoot() < 1e-9)
}

@Test func aRestedBallIgnoresFurtherTime() {
    var flight = BallFlight(launch: launch, aim: SIMD2(0, -1), bounds: bounds)
    settle(&flight)
    let resting = flight
    flight.advance(by: 5)
    #expect(flight == resting)
}
