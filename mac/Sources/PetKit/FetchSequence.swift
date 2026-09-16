import Foundation

/// A desktop fetch trip: the dog runs at a thrown ball while it is still in the air, waits
/// for it to settle if it gets there first, picks it up, turns, carries it back toward
/// wherever the thrower's cursor is, drops it, and celebrates.
///
/// Pure value type with no wall-clock reads. Position and heading are *integrated* rather
/// than interpolated between fixed endpoints (KTD4), which is what lets the ball target move
/// under the dog while it bounces and the return target follow the cursor. `advance(by:)`
/// integrates in fixed substeps, so a single large catch-up step is handled without changing
/// the path.
///
/// Positions are `(x, z)` on the ground plane (`y == 0`, so `SIMD2.x` is world x and
/// `SIMD2.y` is world z). Heading is radians, `0` facing `+z` (toward the camera, the rig's
/// resting orientation), following the `atan2(dx, dz)` convention.
public struct FetchSequence: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// Running at the ball — from the moment of the throw, not the landing.
        case chase
        /// Arrived before the ball settled; standing over it, watching.
        case watch
        case pickup, turnHome, carry, drop, celebrate, done
    }

    /// Authored clip lengths that gate the `pickup` and `celebrate` phases; every other phase
    /// is timed by distance/speed or a fixed turn/drop beat.
    public struct ClipDurations: Sendable, Equatable {
        public var pickup: TimeInterval
        public var happy: TimeInterval

        public init(pickup: TimeInterval, happy: TimeInterval) {
            self.pickup = pickup
            self.happy = happy
        }
    }

    public static let runSpeed: Double = 2.2
    public static let carrySpeed: Double = 1.4
    public static let turnDuration: TimeInterval = 0.2
    public static let dropDuration: TimeInterval = 0.3
    /// How close the mouth has to be to the ball to pick it up.
    public static let pickupRadius: Double = 0.34
    /// How close to the return target counts as home.
    public static let arrivalRadius: Double = 0.06
    /// Heading ease time constant while running; matches `SceneHost`'s wander facing ease so
    /// a chase turn reads the same as a wander turn.
    public static let headingTau: TimeInterval = 0.22
    /// Fixed integration step.
    static let step: TimeInterval = 1.0 / 120

    /// How far toward the camera the ball is set down once carried back: presented in front
    /// of the dog rather than stacked on its paws. Public because the caller must leave this
    /// much depth headroom when it clamps the return target, or the presented ball ends up
    /// past the near edge of the visible ground.
    public static let dropDistance: Double = 0.35

    private let clipDurations: ClipDurations

    /// Live ball position, updated while it bounces (`updateBall`).
    private var ball: SIMD2<Double>
    private var ballAtRest: Bool
    /// Live carry destination, updated from the cursor (`updateReturn`).
    private var returnTarget: SIMD2<Double>
    /// Frozen at the start of `drop` so the dropped ball does not chase a moving cursor.
    private var dropPoint: SIMD2<Double>?

    public private(set) var phase: Phase = .chase
    public private(set) var position: SIMD2<Double>
    public private(set) var heading: Double
    private var phaseElapsed: TimeInterval = 0
    private var carriedBall = false

    /// - Parameters:
    ///   - home: where the dog is standing when the ball is thrown.
    ///   - ball: the ball's predicted rest point, so the chase can start immediately.
    ///   - returnTo: where to carry the ball back to; keep it updated with `updateReturn`.
    public init(
        home: SIMD2<Double>,
        heading: Double = 0,
        ball: SIMD2<Double>,
        returnTo: SIMD2<Double>,
        clipDurations: ClipDurations
    ) {
        self.clipDurations = clipDurations
        self.ball = ball
        self.ballAtRest = false
        self.returnTarget = returnTo
        self.position = home
        self.heading = heading
    }

    // MARK: - Live targets

    /// Feeds the ball's actual position and whether it has stopped. Called every tick while
    /// the flight is running, so the chase converges on where the ball really ends up (R8).
    /// Ignored once the dog has the ball in its mouth.
    public mutating func updateBall(position: SIMD2<Double>, atRest: Bool) {
        guard !carriedBall else { return }
        ball = position
        ballAtRest = atRest
    }

    /// Feeds the spot to carry the ball back to (R10). Ignored once the drop has started.
    public mutating func updateReturn(to target: SIMD2<Double>) {
        guard dropPoint == nil else { return }
        returnTarget = target
    }

    // MARK: - Derived state

    public var clip: String? {
        switch phase {
        case .chase: "shiba_run_loop"
        case .watch: "shiba_alert"
        case .pickup: "shiba_fetch_pickup"
        case .turnHome, .carry, .drop: "shiba_fetch_carry_loop"
        case .celebrate: "shiba_happy"
        case .done: nil
        }
    }

    /// True from the moment the pickup clip finishes through the end of the carry — i.e.
    /// while the ball is in the dog's mouth.
    public var ballAttached: Bool {
        switch phase {
        case .turnHome, .carry: true
        case .chase, .watch, .pickup, .drop, .celebrate, .done: false
        }
    }

    public var ballPosition: SIMD2<Double> {
        switch phase {
        case .chase, .watch, .pickup: ball
        case .turnHome, .carry: position
        case .drop, .celebrate, .done: dropPoint ?? position + SIMD2(0, Self.dropDistance)
        }
    }

    /// Trip length estimated at throw time, for the needs model's play credit (R11). The
    /// chase and carry legs are straight-line estimates; re-targeting makes the real trip
    /// slightly longer, which only means the interaction ends a beat before the celebration
    /// does.
    public var estimatedDuration: TimeInterval {
        let chase = Self.distance(position, ball) / Self.runSpeed
        let carry = Self.distance(ball, returnTarget) / Self.carrySpeed
        return chase + clipDurations.pickup + Self.turnDuration + carry
            + Self.dropDuration + clipDurations.happy
    }

    // MARK: - Advance

    /// Advances the trip by `dt` in fixed substeps. Non-positive or non-finite `dt` is
    /// ignored.
    public mutating func advance(by dt: TimeInterval) {
        guard dt > 0, dt.isFinite else { return }
        var remaining = dt
        while remaining > 0, phase != .done {
            let slice = min(Self.step, remaining)
            remaining -= slice
            substep(slice)
        }
    }

    private mutating func substep(_ dt: TimeInterval) {
        phaseElapsed += dt
        switch phase {
        case .chase:
            let arrived = travel(toward: ball, speed: Self.runSpeed, dt: dt)
            if arrived {
                phase = ballAtRest ? .pickup : .watch
                phaseElapsed = 0
            }
        case .watch:
            face(Self.heading(from: position, to: ball), dt: dt)
            if ballAtRest {
                phase = .pickup
                phaseElapsed = 0
            }
        case .pickup:
            if phaseElapsed >= clipDurations.pickup {
                carriedBall = true
                phase = .turnHome
                phaseElapsed = 0
            }
        case .turnHome:
            face(Self.heading(from: position, to: returnTarget), dt: dt)
            if phaseElapsed >= Self.turnDuration {
                phase = .carry
                phaseElapsed = 0
            }
        case .carry:
            if travel(toward: returnTarget, speed: Self.carrySpeed, dt: dt) {
                phase = .drop
                phaseElapsed = 0
                // Toward the camera, not along the carry heading: the dog arrives facing
                // wherever your cursor was, so a forward drop can push the ball off the
                // panel edge. `+z` puts it between the dog and you, which is also the way
                // `celebrate` turns (R10).
                dropPoint = position + SIMD2(0, Self.dropDistance)
            }
        case .drop:
            if phaseElapsed >= Self.dropDuration {
                phase = .celebrate
                phaseElapsed = 0
            }
        case .celebrate:
            face(0, dt: dt)
            if phaseElapsed >= clipDurations.happy {
                phase = .done
                phaseElapsed = 0
            }
        case .done:
            break
        }
    }

    /// Moves toward `target` at `speed`, easing the heading toward the direction of travel.
    /// Returns `true` once inside the phase's arrival radius.
    ///
    /// Arrival is decided from the analytic remaining distance rather than by re-measuring
    /// after the move: a step capped at `distance - radius` lands on the radius, and the
    /// re-measured value can sit a rounding error outside it, which would leave the dog
    /// circling the ball forever.
    private mutating func travel(toward target: SIMD2<Double>, speed: Double, dt: TimeInterval) -> Bool {
        let radius = phase == .chase ? Self.pickupRadius : Self.arrivalRadius
        let delta = target - position
        let distance = (delta.x * delta.x + delta.y * delta.y).squareRoot()
        guard distance > radius else {
            face(Self.heading(from: position, to: target), dt: dt)
            return true
        }
        let travel = min(speed * dt, distance - radius)
        position += delta / distance * travel
        face(atan2(delta.x, delta.y), dt: dt)
        return distance - travel <= radius + 1e-9
    }

    private mutating func face(_ target: Double, dt: TimeInterval) {
        let delta = Self.normalized(target - heading)
        heading += delta * (1 - exp(-dt / Self.headingTau))
    }

    /// A point `distance` ahead of the dog's muzzle, on the ground.
    private func forwardPoint(_ distance: Double) -> SIMD2<Double> {
        position + SIMD2(sin(heading), cos(heading)) * distance
    }

    // MARK: - Geometry

    private static func distance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let d = b - a
        return (d.x * d.x + d.y * d.y).squareRoot()
    }

    /// `atan2(dx, dz)` so `0` faces `+z`; coincident points have no direction, so they fall
    /// back to facing the camera rather than producing a NaN from `atan2(0, 0)`.
    private static func heading(from a: SIMD2<Double>, to b: SIMD2<Double>) -> Double {
        let dx = b.x - a.x
        let dz = b.y - a.y
        guard dx != 0 || dz != 0 else { return 0 }
        return atan2(dx, dz)
    }

    /// Wraps an angle into `(-π, π]` so a turn never spins the long way round.
    private static func normalized(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi }
        if a < -.pi { a += 2 * .pi }
        return a
    }
}
