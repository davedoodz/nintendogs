import Foundation

/// Decides *what the dog does with its body* while `PetBehavior` holds it in
/// a steady logical state (idle/sit/sleep, with or without a pending care
/// request). Ambient choices are purely visual: they never read or write
/// `PetNeeds`/`PetState`, never persist, and can be re-rolled at any time
/// without corrupting a save — see `docs/ALIVENESS_PLAN.md`.
///
/// Fully deterministic and foreground-driven: every timer advances only via
/// `update(deltaTime:...)`'s `deltaTime`, using a seeded `RandomNumberGenerator`
/// injected at `init` — no wall-clock reads, so a fixed seed reproduces an
/// identical sequence of flourishes for testing. The caller is responsible
/// for only calling `update` with real foreground elapsed time (skip/clamp
/// while the app is backgrounded, the panel hidden, or the system asleep)
/// and for passing `suppressed: true` whenever a care interaction, a manual
/// rest request, or a clip preview is in effect — the director does not
/// infer any of that itself.
///
/// Talks to the rig only through `AnimationController`'s scoped ambient API
/// (`triggerReaction`, `duration(ofClip:)`, `requestGeneration`); it never
/// touches `SceneHost` or root motion.
@MainActor
public final class AmbientDirector {
    /// A small seedable PRNG so tests get a reproducible flourish sequence.
    /// (`SystemRandomNumberGenerator` cannot be seeded.)
    private struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private enum StirPhase: Equatable {
        case none
        case waking(resumeAt: TimeInterval, pause: TimeInterval)
        case pausing(resumeAt: TimeInterval)
    }

    private enum GreetPhase: Equatable {
        case none
        case pendingShake
        case shaking
        case pendingAlert
        case alerting(resumeAt: TimeInterval)
    }

    /// The rare "sit down, hold (maybe scratch), stand back up" idle posture
    /// variation — the only way a dog with good-enough energy to never
    /// logically `.sit` still shows the seated pool/posture change during an
    /// unattended stretch. `scratchAt`/`standAt` are decided up front so
    /// advancing this is a pure elapsed-clock comparison.
    private enum SitVariationPhase: Equatable {
        case none
        case seated(scratchAt: TimeInterval?, standAt: TimeInterval)
    }

    private static let perClipCooldown: TimeInterval = 60
    private static let globalMinGap: TimeInterval = 6
    /// After suppression lifts (care ends, manual rest ends, preview ends),
    /// give the dog a beat before the ambient scheduler can fire again,
    /// instead of an instant fidget on the very tick suppression clears.
    private static let resumeSettleDuration: TimeInterval = 4

    private let controller: AnimationController
    private var rng: SplitMix64

    /// Tuning knob for the debug "Ambient" menu: 0.65 calm / 1.0 natural /
    /// 1.5 lively, matching `StatusMenu`'s picker. Larger = more frequent
    /// (divides every scheduling interval), never changes which pool a clip
    /// is drawn from.
    public var frequencyMultiplier: Double = 1.0

    /// Foreground-only accumulated time; frozen while suppressed.
    private var clock: TimeInterval = 0
    private var wasSuppressed = false

    private var nextFlourishAttemptAt: TimeInterval = 0
    private var nextEligibleFlourishAt: TimeInterval = 0
    private var cooldownUntil: [String: TimeInterval] = [:]
    private var lastClipPlayed: String?

    private var currentBaseLoop = "shiba_idle_loop"
    private var nextLoopSwapAt: TimeInterval = 0

    private var nextSitVariationAt: TimeInterval = 0
    private var sitVariationPhase: SitVariationPhase = .none
    private var sitVariationGeneration = 0

    private var nextStirAt: TimeInterval = 0
    private var stirPhase: StirPhase = .none
    private var stirGeneration = 0
    private var lastActivityForStretchEdge: PetActivity = .idle
    /// Ground truth of the caller's last `update` inputs, refreshed even on
    /// a suppressed call — unlike the scheduling state below, which freezes
    /// while suppressed. Used by `setAttention`, which can be called at any
    /// time regardless of suppression.
    private var currentKnownActivity: PetActivity = .idle
    private var isSuppressedNow = false

    private var greetPhase: GreetPhase = .none
    private var greetGeneration = 0

    private var isHovering = false
    private var hoverElapsed: TimeInterval = 0
    private var alertFiredForHover = false
    private var happyFiredForHover = false

    private var externalLocomotionActive = false

    public init(controller: AnimationController, seed: UInt64 = .random(in: .min ... .max)) {
        self.controller = controller
        var rng = SplitMix64(seed: seed)
        self.nextFlourishAttemptAt = Double.random(in: 8...25, using: &rng)
        self.nextLoopSwapAt = Double.random(in: 20...40, using: &rng)
        self.nextSitVariationAt = Double.random(in: 90...180, using: &rng)
        self.nextStirAt = Double.random(in: 120...240, using: &rng)
        self.rng = rng
    }

    /// Call every foreground frame tick (the app's existing ~30Hz loop).
    /// `deltaTime` must already exclude backgrounded/suspended time.
    /// `suppressed` should be `isInteracting || isRestingOnRequest ||
    /// previewing`; while `true` the director advances nothing at all (no
    /// RNG draw, no timer, no clip trigger) so it's safe to call
    /// unconditionally rather than gating the call site. `hour` is the
    /// caller's local hour-of-day (0-23, default noon), used only for
    /// coarse morning/evening/night bias — the director itself never reads
    /// a clock.
    public func update(
        deltaTime: TimeInterval,
        needs: PetNeeds,
        activity: PetActivity,
        careRequest: Bool,
        suppressed: Bool,
        hour: Int = 12
    ) {
        guard deltaTime > 0, deltaTime.isFinite else { return }
        currentKnownActivity = activity
        isSuppressedNow = suppressed
        guard !suppressed else {
            wasSuppressed = true
            stirPhase = .none
            sitVariationPhase = .none
            greetPhase = .none
            return
        }
        if wasSuppressed {
            wasSuppressed = false
            let settleUntil = clock + Self.resumeSettleDuration
            nextFlourishAttemptAt = max(nextFlourishAttemptAt, settleUntil)
            nextEligibleFlourishAt = max(nextEligibleFlourishAt, settleUntil)
            nextLoopSwapAt = max(nextLoopSwapAt, settleUntil)
            nextSitVariationAt = max(nextSitVariationAt, settleUntil)
            nextStirAt = max(nextStirAt, settleUntil)
        }
        clock += deltaTime

        if activity == .sleep, lastActivityForStretchEdge != .sleep {
            let morning = hour >= 6 && hour < 10
            if Double.random(in: 0..<1, using: &rng) < (morning ? 0.8 : 0.5) {
                controller.preferStretchOnNextWake()
            }
        }
        lastActivityForStretchEdge = activity
        if activity != .idle {
            currentBaseLoop = "shiba_idle_loop"
        }

        advanceGreet()
        advanceStir(activity: activity)
        advanceSitVariation(activity: activity, careRequest: careRequest)
        advanceHover(deltaTime: deltaTime, activity: activity, careRequest: careRequest)

        guard stirPhase == .none, greetPhase == .none, sitVariationPhase == .none else { return }
        guard !externalLocomotionActive else { return }

        let night = Self.isNight(hour)
        switch (activity, careRequest) {
        case (.idle, true):
            scheduleBegPool()
        case (.idle, false):
            if !scheduleSitVariation(needs: needs, night: night) {
                scheduleIdlePool(needs: needs, hour: hour, night: night)
                scheduleBaseLoopSwap(needs: needs)
            }
        case (.sit, _):
            scheduleSitPool(needs: needs)
        case (.sleep, _):
            scheduleStirTimer()
        case (.eat, _), (.drink, _), (.play, _), (.call, _), (.pet, _), (.fetch, _):
            break // momentary interactions: parent should already be passing `suppressed: true`
        }
    }

    /// Cursor hover lifecycle from `SceneHost`'s `cursorAttention`. The
    /// parent separately feeds the *affection* side effect to
    /// `PetBehavior.noticeAttention`; this only owns the alert/happy timing.
    public func setAttention(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        if hovering {
            hoverElapsed = 0
            alertFiredForHover = false
            happyFiredForHover = false
        } else if alertFiredForHover, !isSuppressedNow, !externalLocomotionActive,
                  stirPhase == .none, greetPhase == .none, sitVariationPhase == .none,
                  currentKnownActivity == .idle {
            // Looked away after real attention: one parting scan, reusing
            // the same base-loop-swap mechanism as the ambient cadence.
            switchBaseLoop(to: "shiba_look_around_loop")
        }
    }

    /// Parent-driven wander/locomotion (`SceneHost`) is in progress —
    /// pauses idle flourishes and the base-loop swap so they don't fight
    /// root motion. Does not affect the sleep stir or sit variation, which
    /// only ever run while genuinely idle/asleep, never while wandering.
    public func setExternalLocomotion(_ active: Bool) {
        externalLocomotionActive = active
    }

    /// One-shot wake/return greeting: routes to standing (waking up first if
    /// asleep — `lying → wake → stand_from_sit` — otherwise a direct
    /// standing alert), holds alert, then happy. Retries every tick until
    /// `AnimationController` can actually accept it instead of being lost if
    /// a logical route/interaction is still in flight.
    public func greet(morning: Bool = false) {
        guard greetPhase == .none else { return }
        greetPhase = morning ? .pendingShake : .pendingAlert
    }

    // MARK: - Idle/sit flourish pools

    private func scheduleIdlePool(needs: PetNeeds, hour: Int, night: Bool) {
        guard attemptGate(interval: night ? 25...80 : 8...25) else { return }
        let yawnWeight = (needs.energy < 40 ? 3.0 : 1.0) * (Self.isEveningOrNight(hour) ? 2.0 : 1.0)
        let bored = needs.fun < 40
        let liked = needs.fun > 70 || needs.affection > 70
        let happyWeight = bored ? 0.0 : (liked ? 2.0 : 1.0)
        let barkWeight = liked ? 1.5 : 1.0
        let shakeWeight = needs.cleanliness < 40 ? 3.0 : 1.0
        let pool: [(clip: String, weight: Double)] = [
            ("shiba_yawn", yawnWeight),
            ("shiba_shake", shakeWeight),
            ("shiba_alert", 0.5),
            ("shiba_bark", barkWeight),
            ("shiba_happy", happyWeight),
        ]
        fireFlourish(from: pool)
    }

    private func scheduleSitPool(needs: PetNeeds) {
        guard attemptGate(interval: 8...25) else { return }
        let scratchWeight = needs.cleanliness < 40 ? 3.0 : 1.0
        fireFlourish(from: [("shiba_scratch", scratchWeight)])
    }

    private func scheduleBegPool() {
        guard attemptGate(interval: 20...40) else { return }
        fireFlourish(from: [("shiba_bark", 1.0)])
    }

    /// `true` exactly on the tick a scheduling attempt is due; always
    /// reschedules the next attempt so callers don't need their own timer.
    private func attemptGate(interval: ClosedRange<Double>) -> Bool {
        guard clock >= nextFlourishAttemptAt else { return false }
        nextFlourishAttemptAt = clock + randomInterval(interval)
        return clock >= nextEligibleFlourishAt
    }

    private func fireFlourish(from pool: [(clip: String, weight: Double)]) {
        guard let clip = weightedPick(pool) else { return }
        guard controller.triggerReaction(clip) else { return }
        cooldownUntil[clip] = clock + Self.perClipCooldown
        nextEligibleFlourishAt = clock + Self.globalMinGap
        lastClipPlayed = clip
    }

    private func weightedPick(_ pool: [(clip: String, weight: Double)]) -> String? {
        let eligible = pool.filter {
            $0.weight > 0 && ($0.clip != lastClipPlayed || pool.count == 1) && clock >= (cooldownUntil[$0.clip] ?? 0)
        }
        let total = eligible.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        var roll = Double.random(in: 0..<total, using: &rng)
        for entry in eligible {
            if roll < entry.weight { return entry.clip }
            roll -= entry.weight
        }
        return eligible.last?.clip
    }

    // MARK: - Idle base-loop swap (idle_loop <-> look_around_loop)

    private func scheduleBaseLoopSwap(needs: PetNeeds) {
        guard clock >= nextLoopSwapAt else { return }
        let bored = needs.fun < 40
        nextLoopSwapAt = clock + randomInterval(bored ? 10...25 : 20...40)
        let next = currentBaseLoop == "shiba_idle_loop" ? "shiba_look_around_loop" : "shiba_idle_loop"
        switchBaseLoop(to: next)
    }

    private func switchBaseLoop(to clip: String) {
        guard controller.triggerReaction(clip) else { return }
        currentBaseLoop = clip
        nextLoopSwapAt = clock + randomInterval(20...40)
    }

    // MARK: - Idle sit-down/scratch/stand variation

    /// Returns `true` iff it started this tick, so the caller can skip the
    /// ordinary idle pool/base-loop swap for the same tick.
    @discardableResult
    private func scheduleSitVariation(needs: PetNeeds, night: Bool) -> Bool {
        guard sitVariationPhase == .none, clock >= nextSitVariationAt else { return false }
        let healthyBias = needs.energy > 60 ? 1.4 : 1.0
        nextSitVariationAt = clock + randomInterval(night ? 240...420 : 90...180) / healthyBias
        guard controller.triggerReaction("shiba_sit", thenReturnToRest: false) else { return false }
        sitVariationGeneration = controller.requestGeneration
        let sitDuration = controller.duration(ofClip: "shiba_sit") ?? 2
        let hold = randomInterval(8...15)
        let scratchChance = needs.cleanliness < 40 ? 0.75 : 0.3
        let scratchAt: TimeInterval? = Double.random(in: 0..<1, using: &rng) < scratchChance
            ? clock + sitDuration + hold * 0.4
            : nil
        sitVariationPhase = .seated(scratchAt: scratchAt, standAt: clock + sitDuration + hold)
        return true
    }

    private func advanceSitVariation(activity: PetActivity, careRequest: Bool) {
        guard case .seated(let scratchAt, let standAt) = sitVariationPhase else { return }
        guard controller.requestGeneration == sitVariationGeneration else {
            sitVariationPhase = .none
            return
        }
        guard activity == .idle, !careRequest else {
            sitVariationPhase = .none
            return
        }
        if let scratchAt, clock >= scratchAt {
            guard controller.triggerReaction("shiba_scratch", thenReturnToRest: false) else { return }
            sitVariationPhase = .seated(scratchAt: nil, standAt: standAt)
            return
        }
        if clock >= standAt {
            guard controller.triggerReaction("shiba_stand_from_sit") else { return }
            sitVariationPhase = .none
        } else if controller.isReadyForAmbient,
                  controller.currentClip == "shiba_sit" || controller.currentClip == "shiba_scratch" {
            _ = controller.triggerReaction("shiba_sit_idle_loop")
        }
    }

    // MARK: - Sleep stir

    private func scheduleStirTimer() {
        guard stirPhase == .none, clock >= nextStirAt else { return }
        guard controller.triggerReaction("shiba_wake", thenReturnToRest: false) else {
            nextStirAt = clock + randomInterval(120...240)
            return
        }
        stirGeneration = controller.requestGeneration
        let wakeDuration = controller.duration(ofClip: "shiba_wake") ?? 2
        let pause = randomInterval(2...4)
        stirPhase = .waking(resumeAt: clock + wakeDuration, pause: pause)
    }

    private func advanceStir(activity: PetActivity) {
        switch stirPhase {
        case .none:
            return
        case .waking(let resumeAt, let pause):
            guard controller.requestGeneration == stirGeneration else { stirPhase = .none; return }
            guard activity == .sleep else { stirPhase = .none; return }
            guard clock >= resumeAt else { return }
            stirPhase = .pausing(resumeAt: clock + pause)
        case .pausing(let resumeAt):
            guard controller.requestGeneration == stirGeneration else { stirPhase = .none; return }
            guard activity == .sleep else { stirPhase = .none; return }
            guard clock >= resumeAt else { return }
            guard controller.triggerReaction("shiba_lie_down") else { return }
            stirPhase = .none
            nextStirAt = clock + randomInterval(120...240)
        }
    }

    // MARK: - Greeting

    private func advanceGreet() {
        switch greetPhase {
        case .none:
            return
        case .pendingShake:
            guard controller.triggerReaction("shiba_shake", thenReturnToRest: false) else { return }
            greetGeneration = controller.requestGeneration
            greetPhase = .shaking
        case .shaking:
            guard controller.requestGeneration == greetGeneration else { greetPhase = .none; return }
            guard controller.isReadyForAmbient else { return }
            greetPhase = .pendingAlert
        case .pendingAlert:
            // Retries every tick — never lost if a logical route/interaction
            // is still in flight when `greet()` was called.
            guard controller.triggerReaction("shiba_alert", thenReturnToRest: false) else { return }
            greetGeneration = controller.requestGeneration
            let alertDuration = controller.duration(ofClip: "shiba_alert") ?? 0.5
            greetPhase = .alerting(resumeAt: clock + alertDuration)
        case .alerting(let resumeAt):
            guard controller.requestGeneration == greetGeneration else { greetPhase = .none; return }
            guard clock >= resumeAt else { return }
            guard controller.triggerReaction("shiba_happy") else { return }
            greetPhase = .none
        }
    }

    // MARK: - Cursor attention (alert/happy timing only; affection is the parent's job)

    private func advanceHover(deltaTime: TimeInterval, activity: PetActivity, careRequest: Bool) {
        guard isHovering, activity == .idle || activity == .sit, !careRequest else { return }
        guard stirPhase == .none, greetPhase == .none, sitVariationPhase == .none else { return }
        hoverElapsed += deltaTime
        if !alertFiredForHover, hoverElapsed >= 1.5 {
            if controller.triggerReaction("shiba_alert") { alertFiredForHover = true }
        } else if alertFiredForHover, !happyFiredForHover, hoverElapsed >= 4.0 {
            if controller.triggerReaction("shiba_happy") { happyFiredForHover = true }
        }
    }

    // MARK: - Time-of-day helpers (caller-supplied hour; no clock reads here)

    private static func isNight(_ hour: Int) -> Bool { hour >= 22 || hour < 7 }
    private static func isEveningOrNight(_ hour: Int) -> Bool { hour >= 20 || hour < 7 }

    private func randomInterval(_ range: ClosedRange<Double>) -> TimeInterval {
        Double.random(in: range, using: &rng) / max(frequencyMultiplier, 0.01)
    }
}
