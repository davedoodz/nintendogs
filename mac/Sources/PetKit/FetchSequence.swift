import Foundation

/// A deterministic desktop fetch trip: the dog turns to a thrown ball, runs
/// to it, picks it up, turns back, carries it home, drops it, and
/// celebrates. Pure value type with no wall-clock reads, so the app's
/// fixed-step loop can call `advance(by:)` with whatever `dt` it has,
/// including a single large catch-up step that crosses several phases.
///
/// Positions are `(x, z)` on the ground plane (`y == 0`, so `SIMD2.x` is
/// world x and `SIMD2.y` is world z). Heading is radians, `0` facing `+z`
/// (toward the camera, the rig's resting orientation), following the
/// `atan2(dx, dz)` convention.
public struct FetchSequence: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case turnToBall, run, pickup, turnHome, carry, drop, celebrate, done
    }

    /// Authored clip lengths that gate the `pickup` and `celebrate` phases;
    /// every other phase is timed by distance/speed or a fixed turn/drop beat.
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

    /// Where the ball rests relative to `home` once dropped: a little in
    /// front of the dog, not stacked on its feet.
    private static let dropOffset = SIMD2<Double>(0.35, 0.3)

    private let home: SIMD2<Double>
    private let ball: SIMD2<Double>
    private let clipDurations: ClipDurations
    private let headingToBall: Double
    private let headingToHome: Double
    private let runDuration: TimeInterval
    private let carryDuration: TimeInterval

    public private(set) var phase: Phase = .turnToBall
    private var phaseElapsed: TimeInterval = 0

    public init(home: SIMD2<Double>, ball: SIMD2<Double>, clipDurations: ClipDurations) {
        self.home = home
        self.ball = ball
        self.clipDurations = clipDurations
        self.headingToBall = Self.heading(from: home, to: ball)
        self.headingToHome = Self.heading(from: ball, to: home)
        self.runDuration = Self.distance(home, ball) / Self.runSpeed
        self.carryDuration = Self.distance(ball, home) / Self.carrySpeed
    }

    // MARK: - Derived state

    public var position: SIMD2<Double> {
        switch phase {
        case .turnToBall:
            home
        case .run:
            Self.lerp(home, ball, runDuration > 0 ? phaseElapsed / runDuration : 1)
        case .pickup, .turnHome:
            ball
        case .carry:
            Self.lerp(ball, home, carryDuration > 0 ? phaseElapsed / carryDuration : 1)
        case .drop, .celebrate, .done:
            home
        }
    }

    public var heading: Double {
        switch phase {
        case .turnToBall:
            Self.lerpAngle(0, headingToBall, phaseElapsed / Self.turnDuration)
        case .run, .pickup:
            headingToBall
        case .turnHome:
            Self.lerpAngle(headingToBall, headingToHome, phaseElapsed / Self.turnDuration)
        case .carry:
            headingToHome
        case .drop, .celebrate, .done:
            0
        }
    }

    public var clip: String? {
        switch phase {
        case .turnToBall, .run: "shiba_run_loop"
        case .pickup: "shiba_fetch_pickup"
        case .turnHome, .carry, .drop: "shiba_fetch_carry_loop"
        case .celebrate: "shiba_happy"
        case .done: nil
        }
    }

    /// True from the moment the pickup clip finishes through the end of
    /// carrying — i.e. while the ball is in the dog's mouth.
    public var ballAttached: Bool {
        switch phase {
        case .turnHome, .carry: true
        case .turnToBall, .run, .pickup, .drop, .celebrate, .done: false
        }
    }

    public var ballPosition: SIMD2<Double> {
        switch phase {
        case .turnToBall, .run, .pickup:
            ball
        case .turnHome, .carry:
            position
        case .drop, .celebrate, .done:
            home + Self.dropOffset
        }
    }

    /// Sum of every phase's duration; independent of how far the sequence
    /// has advanced.
    public var totalDuration: TimeInterval {
        Self.turnDuration + runDuration + clipDurations.pickup + Self.turnDuration
            + carryDuration + Self.dropDuration + clipDurations.happy
    }

    // MARK: - Advance

    /// Advances the sequence by `dt`, carrying leftover time across phase
    /// boundaries within this single call — a large `dt` can run through
    /// several phases (including zero-length ones) before returning.
    /// Non-positive or non-finite `dt` is ignored.
    public mutating func advance(by dt: TimeInterval) {
        guard dt > 0, dt.isFinite else { return }
        var remaining = dt
        while remaining > 0, phase != .done {
            let left = duration(of: phase) - phaseElapsed
            if remaining < left {
                phaseElapsed += remaining
                remaining = 0
            } else {
                remaining -= left
                advancePhase()
            }
        }
    }

    private mutating func advancePhase() {
        phaseElapsed = 0
        switch phase {
        case .turnToBall: phase = .run
        case .run: phase = .pickup
        case .pickup: phase = .turnHome
        case .turnHome: phase = .carry
        case .carry: phase = .drop
        case .drop: phase = .celebrate
        case .celebrate: phase = .done
        case .done: break
        }
    }

    private func duration(of phase: Phase) -> TimeInterval {
        switch phase {
        case .turnToBall, .turnHome: Self.turnDuration
        case .run: runDuration
        case .pickup: clipDurations.pickup
        case .carry: carryDuration
        case .drop: Self.dropDuration
        case .celebrate: clipDurations.happy
        case .done: 0
        }
    }

    // MARK: - Geometry

    private static func distance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let d = b - a
        return (d.x * d.x + d.y * d.y).squareRoot()
    }

    /// `atan2(dx, dz)` so `0` faces `+z`; the zero vector (coincident points)
    /// has no direction, so it falls back to facing the camera rather than
    /// producing a NaN from `atan2(0, 0)`.
    private static func heading(from a: SIMD2<Double>, to b: SIMD2<Double>) -> Double {
        let dx = b.x - a.x
        let dz = b.y - a.y
        guard dx != 0 || dz != 0 else { return 0 }
        return atan2(dx, dz)
    }

    private static func lerp(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ t: Double) -> SIMD2<Double> {
        a + (b - a) * t
    }

    /// Linear angle interpolation along the shorter arc, so a turn never
    /// spins the long way around through the `±π` branch cut.
    private static func lerpAngle(_ a: Double, _ b: Double, _ t: Double) -> Double {
        var delta = (b - a).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return a + delta * t
    }
}
