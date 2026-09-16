import Foundation

/// A thrown tennis ball: ballistic arc, bounces, roll-out, rest.
///
/// Pure value type with no wall-clock reads and no SceneKit dependency, advanced in fixed
/// substeps (KTD1) so the same throw always produces the same trajectory regardless of how
/// the app's loop slices `dt`. That is what makes `predictedRest` — the same struct advanced
/// to rest on a copy — *exactly* the spot the rendered ball ends up on, which the dog's chase
/// depends on (KTD2, R8).
///
/// Positions are world `(x, y, z)` with `y` up and the ground plane at `y == 0`; the ball
/// rests at `y == radius`.
public struct BallFlight: Sendable, Equatable {
    /// The ground rectangle the ball may occupy — the same clamps the aim ray applies, so a
    /// throw can never come to rest somewhere the thrower could not have aimed (KTD3).
    public struct Bounds: Sendable, Equatable {
        public var xLimit: Double
        public var zNear: Double
        public var zFar: Double

        public init(xLimit: Double, zNear: Double, zFar: Double) {
            self.xLimit = xLimit
            self.zNear = zNear
            self.zFar = zFar
        }
    }

    public static let radius: Double = 0.08

    /// Scaled for a 1-unit-tall dog rather than a real 0.4 m one: full gravity on this scale
    /// makes the flight read as a dropped marble. 5.4 keeps hang time close to a real throw
    /// across a room while the arc still looks like weight.
    static let gravity: Double = 5.4
    /// Restitution and drag are tuned by measurement rather than physics tables: the target
    /// is two visible hops and a short roll that carries the ball 25-40% past the aimed spot
    /// across the whole throw range, settling in ~1.5-2.1 s — before the dog gets there on a
    /// long throw, so the chase rarely has to wait.
    static let restitution: Double = 0.42
    /// Horizontal speed kept through an impact (surface drag, no spin model).
    static let bounceDamping: Double = 0.45
    /// Horizontal speed kept when a bounce collapses into a roll.
    static let settleDamping: Double = 0.5
    /// Rolling friction, in world units per second squared.
    static let rollDeceleration: Double = 3.4
    /// Below this downward speed an impact is a settle, not a bounce.
    static let bounceThreshold: Double = 0.7
    /// A roll slower than this has stopped.
    static let restThreshold: Double = 0.06
    /// Fixed integration step (KTD1).
    static let step: TimeInterval = 1.0 / 240
    /// Hard cap on `predictedRest`'s simulation, so a pathological model can never spin.
    static let maxSimulatedFlight: TimeInterval = 8

    public private(set) var position: SIMD3<Double>
    public private(set) var velocity: SIMD3<Double>
    /// True once the ball has stopped moving; `advance(by:)` is then a no-op.
    public private(set) var isAtRest = false
    /// True once the ball is on the ground and only losing speed to friction.
    public private(set) var isRolling = false
    /// Impacts that rebounded. Increments only on real bounces, so a renderer can use a change
    /// as the cue for a squash or a sound.
    public private(set) var bounceCount = 0
    /// Distance travelled along the ground, for rolling the ball's own spin.
    public private(set) var travelled: Double = 0

    private let bounds: Bounds
    private var residual: TimeInterval = 0

    public var groundPosition: SIMD2<Double> { SIMD2(position.x, position.z) }
    public var height: Double { position.y }

    /// Launches a ball from `launch` so that its **first impact** is `aim` (KTD2): the aim
    /// marker stays truthful, and everything past that impact is emergent.
    ///
    /// Flight time scales with distance so a short toss is not slow-motion and a long throw
    /// still arcs; the vertical speed is then whatever puts the ball on the ground at the end
    /// of that time.
    public init(launch: SIMD3<Double>, aim: SIMD2<Double>, bounds: Bounds) {
        self.bounds = bounds
        let target = SIMD2(
            min(max(aim.x, -bounds.xLimit), bounds.xLimit),
            min(max(aim.y, bounds.zFar), bounds.zNear)
        )
        let delta = target - SIMD2(launch.x, launch.z)
        let distance = (delta.x * delta.x + delta.y * delta.y).squareRoot()
        let time = min(max(distance / 4.5, 0.3), 1.05)
        let drop = Self.radius - launch.y
        position = launch
        velocity = SIMD3(
            delta.x / time,
            (drop + 0.5 * Self.gravity * time * time) / time,
            delta.y / time
        )
    }

    /// Advances the ball by `dt`, in fixed substeps with the remainder carried to the next
    /// call. A non-positive or non-finite `dt` is ignored.
    public mutating func advance(by dt: TimeInterval) {
        guard dt > 0, dt.isFinite, !isAtRest else { return }
        residual += dt
        while residual >= Self.step, !isAtRest {
            residual -= Self.step
            substep()
        }
    }

    /// Where this ball will come to rest, simulated on a copy. Exact rather than estimated:
    /// the copy runs the same fixed-step integrator, so the chase target and the rendered
    /// resting ball agree (R8).
    public var predictedRest: SIMD2<Double> {
        var copy = self
        copy.residual = 0
        var elapsed: TimeInterval = 0
        while !copy.isAtRest, elapsed < Self.maxSimulatedFlight {
            copy.substep()
            elapsed += Self.step
        }
        return copy.groundPosition
    }

    private mutating func substep() {
        if isRolling {
            let speed = (velocity.x * velocity.x + velocity.z * velocity.z).squareRoot()
            guard speed > Self.restThreshold else {
                velocity = .zero
                isAtRest = true
                return
            }
            let slowed = max(0, speed - Self.rollDeceleration * Self.step)
            velocity.x *= slowed / speed
            velocity.z *= slowed / speed
            position.y = Self.radius
            velocity.y = 0
        } else {
            velocity.y -= Self.gravity * Self.step
        }

        let before = SIMD2(position.x, position.z)
        position += velocity * Self.step
        clampToBounds()
        let after = SIMD2(position.x, position.z)
        travelled += ((after.x - before.x) * (after.x - before.x)
            + (after.y - before.y) * (after.y - before.y)).squareRoot()

        guard !isRolling, position.y <= Self.radius, velocity.y < 0 else { return }
        position.y = Self.radius
        if -velocity.y < Self.bounceThreshold {
            isRolling = true
            velocity.y = 0
            velocity.x *= Self.settleDamping
            velocity.z *= Self.settleDamping
        } else {
            velocity.y = -velocity.y * Self.restitution
            velocity.x *= Self.bounceDamping
            velocity.z *= Self.bounceDamping
            bounceCount += 1
        }
    }

    /// Stops a component that is being driven *further* outside the arena. Direction matters:
    /// the ball is launched from in front of the near bound (the dog throws from beside the
    /// camera), so an unconditional clamp would pin it at the boundary on its first substep
    /// instead of letting it travel inward. Inside the substep, so `predictedRest` and the
    /// rendered flight clamp identically (KTD3).
    private mutating func clampToBounds() {
        if position.x < -bounds.xLimit, velocity.x < 0 {
            position.x = -bounds.xLimit
            velocity.x = 0
        } else if position.x > bounds.xLimit, velocity.x > 0 {
            position.x = bounds.xLimit
            velocity.x = 0
        }
        if position.z < bounds.zFar, velocity.z < 0 {
            position.z = bounds.zFar
            velocity.z = 0
        } else if position.z > bounds.zNear, velocity.z > 0 {
            position.z = bounds.zNear
            velocity.z = 0
        }
    }
}
