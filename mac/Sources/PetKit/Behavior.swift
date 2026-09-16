import Foundation

/// Drives a `PetState` forward in time and applies interactions. All timing is
/// injected (`Date` in, no wall-clock reads), so the whole loop is deterministic
/// and testable, and safe to catch up across an arbitrary offline gap.
///
/// ## Rates (per second of simulated time)
/// - Deficits drift up, meters drift down, at real-time paces tuned so a pet
///   left alone needs attention on a human timescale rather than a DS-session one:
///   - hunger: `+100 / 6h` (fully starving after 6h uncared-for)
///   - thirst: `+100 / 4h`
///   - fun: `-100 / 5h`
///   - cleanliness: `-100 / 30h` (no in-scope activity restores this yet)
///   - affection: `-100 / 72h`
///   - energy: `-100 / 18h` while awake, `+100 / 8h` while asleep, flat while `sit`ting
///     (resting pauses the drain without a full sleep recovery), with an extra
///     `-100 / 3h` on top of the awake drain while `play`ing.
/// - Momentary interactions replenish/boost their target meter(s) linearly over
///   their fixed duration, reaching a full swing (0↔100) if run start-to-finish:
///   `eat` 10s (hunger), `drink` 6s (thirst), `play` 12s (+100 fun, +20 affection),
///   `pet` 5s (+100 affection, +10 fun), `call` 2s (+5 affection, wakes from sleep).
///   All other meters keep drifting normally during an interaction except the
///   one(s) it targets.
/// - Offline/behind-schedule catch-up is capped at 12h of simulated drift: a
///   longer real gap still only advances the meters by 12h worth, then stamps
///   `lastUpdated` to the real `at` so the next tick resumes from now.
/// - A clock that moves backward (`at < state.lastUpdated`) is a no-op: no
///   negative drift, `lastUpdated` does not move.
public struct PetBehavior: Sendable {
    public var state: PetState

    /// Set only while a momentary interaction (`eat`/`drink`/`play`/`pet`/`call`)
    /// is running; not part of `PetState`, so it never persists and never survives
    /// a relaunch — see `init(state:)`.
    private var interactionEndsAt: Date?
    private var manualRestUntil: Date?

    private static let maxCatchUp: TimeInterval = 12 * 3600
    private static let stepSize: TimeInterval = 1

    /// Below this energy the pet prefers to `sit` over `idle`.
    private static let restEnergyThreshold: Double = 35
    /// At/above this hunger or thirst, the pet won't autonomously sleep — it
    /// stays up (idle/sit) so the UI can surface `PetState.careRequest`.
    private static let criticalDeficit: Double = 85

    private static let hungerDriftPerSecond = 100.0 / (6 * 3600)
    private static let thirstDriftPerSecond = 100.0 / (4 * 3600)
    private static let funDriftPerSecond = -100.0 / (5 * 3600)
    private static let cleanlinessDriftPerSecond = -100.0 / (30 * 3600)
    private static let affectionDriftPerSecond = -100.0 / (72 * 3600)

    private static let energyAwakeDrainPerSecond = 100.0 / (18 * 3600)
    private static let energySleepRecoverPerSecond = 100.0 / (8 * 3600)
    private static let energyPlayExtraDrainPerSecond = 100.0 / (3 * 3600)

    private static let eatDuration: TimeInterval = 10
    private static let drinkDuration: TimeInterval = 6
    private static let playDuration: TimeInterval = 12
    private static let petDuration: TimeInterval = 5
    private static let callDuration: TimeInterval = 2

    private static let hungerReliefPerSecond = 100.0 / eatDuration
    private static let thirstReliefPerSecond = 100.0 / drinkDuration
    private static let funGainPerSecondPlay = 100.0 / playDuration
    private static let affectionGainPerSecondPlay = 20.0 / playDuration
    private static let affectionGainPerSecondPet = 100.0 / petDuration
    private static let funGainPerSecondPet = 10.0 / petDuration
    private static let affectionGainPerSecondCall = 5.0 / callDuration

    public init(state: PetState) {
        var normalized = state
        // A momentary interaction can't safely resume after being unobserved
        // (process relaunch, long background gap): its remaining duration is
        // unknown, so treat it as already finished and let the first tick
        // re-derive an autonomous activity from a clean baseline.
        if Self.duration(for: normalized.activity) != nil {
            normalized.activity = .idle
        }
        normalized.needs.clamp()
        self.state = normalized
        self.interactionEndsAt = nil
    }

    /// Advances `state` from `state.lastUpdated` to `at`, in 1-second steps,
    /// capped at 12h of simulated drift. No-ops if `at` is not after `lastUpdated`.
    public mutating func tick(at date: Date, calendar: Calendar = .current) {
        guard date > state.lastUpdated else { return }
        let elapsed = min(date.timeIntervalSince(state.lastUpdated), Self.maxCatchUp)
        var cursor = date.addingTimeInterval(-elapsed)
        var remaining = elapsed
        while remaining > 0 {
            let dt = min(Self.stepSize, remaining)
            cursor = cursor.addingTimeInterval(dt)
            step(dt: dt, at: cursor, calendar: calendar)
            remaining -= dt
        }
        state.lastUpdated = date
    }

    /// Preempts whatever the pet is doing (including an in-progress interaction
    /// or sleep) with `activity`. Momentary activities run for their fixed
    /// duration and then hand back control to autonomous selection; `idle`/`sit`/
    /// `sleep` are applied immediately with no protected duration.
    public mutating func interact(_ activity: PetActivity, at date: Date) {
        guard date >= state.lastUpdated else { return }
        tick(at: date, calendar: .current)
        manualRestUntil = activity == .sleep ? date.addingTimeInterval(15 * 60) : nil
        state.activity = activity
        interactionEndsAt = Self.duration(for: activity).map { date.addingTimeInterval($0) }
    }

    private mutating func step(dt: TimeInterval, at cursor: Date, calendar: Calendar) {
        if let endsAt = interactionEndsAt {
            let start = cursor.addingTimeInterval(-dt)
            let interactionTime = max(0, min(dt, endsAt.timeIntervalSince(start)))
            applyInteraction(state.activity, dt: interactionTime)
            if cursor >= endsAt {
                interactionEndsAt = nil
                let night = Self.isNight(cursor, calendar: calendar)
                state.activity = Self.resolveAutonomousActivity(needs: state.needs, previous: state.activity, night: night)
                applyAutonomous(state.activity, dt: dt - interactionTime)
            }
        } else {
            let night = Self.isNight(cursor, calendar: calendar)
            state.activity = (manualRestUntil.map { cursor < $0 } ?? false)
                ? .sleep
                : Self.resolveAutonomousActivity(needs: state.needs, previous: state.activity, night: night)
            applyAutonomous(state.activity, dt: dt)
        }
        state.needs.clamp()
    }

    // MARK: - Autonomous selection (utility-based: idle/sit/sleep)

    private static func resolveAutonomousActivity(needs: PetNeeds, previous: PetActivity, night: Bool) -> PetActivity {
        let critical = needs.hunger >= criticalDeficit || needs.thirst >= criticalDeficit
        let canSleep = needs.energy < 25 || (!critical && (night || (previous == .sleep && needs.energy < 60)))
        let sleepUtility: Double
        if canSleep {
            let desire = (night ? 110 : 100) - needs.energy
            let hysteresis = previous == .sleep ? 15.0 : 0.0
            sleepUtility = desire + hysteresis
        } else {
            sleepUtility = -.infinity
        }
        let sitUtility = max(0, restEnergyThreshold - needs.energy)
        let idleUtility = 5.0

        if sleepUtility > sitUtility, sleepUtility > idleUtility { return .sleep }
        if sitUtility > idleUtility { return .sit }
        return .idle
    }

    private static func isNight(_ date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 22 || hour < 7
    }

    // MARK: - Meter drift

    private enum NeedKind: Hashable {
        case hunger, thirst, fun, affection
    }

    private mutating func applyAutonomous(_ activity: PetActivity, dt: TimeInterval) {
        switch activity {
        case .sleep:
            state.needs.energy += Self.energySleepRecoverPerSecond * dt
        case .sit:
            break
        case .idle, .eat, .drink, .play, .call, .pet:
            state.needs.energy -= Self.energyAwakeDrainPerSecond * dt
        }
        applyPassiveDrift(dt: dt, excluding: [])
    }

    private mutating func applyInteraction(_ activity: PetActivity, dt: TimeInterval) {
        switch activity {
        case .eat:
            state.needs.hunger -= Self.hungerReliefPerSecond * dt
            state.needs.energy -= Self.energyAwakeDrainPerSecond * dt
            applyPassiveDrift(dt: dt, excluding: [.hunger])
        case .drink:
            state.needs.thirst -= Self.thirstReliefPerSecond * dt
            state.needs.energy -= Self.energyAwakeDrainPerSecond * dt
            applyPassiveDrift(dt: dt, excluding: [.thirst])
        case .play:
            state.needs.fun += Self.funGainPerSecondPlay * dt
            state.needs.affection += Self.affectionGainPerSecondPlay * dt
            state.needs.energy -= (Self.energyAwakeDrainPerSecond + Self.energyPlayExtraDrainPerSecond) * dt
            applyPassiveDrift(dt: dt, excluding: [.fun, .affection])
        case .pet:
            state.needs.affection += Self.affectionGainPerSecondPet * dt
            state.needs.fun += Self.funGainPerSecondPet * dt
            state.needs.energy -= Self.energyAwakeDrainPerSecond * dt
            applyPassiveDrift(dt: dt, excluding: [.affection, .fun])
        case .call:
            state.needs.affection += Self.affectionGainPerSecondCall * dt
            state.needs.energy -= Self.energyAwakeDrainPerSecond * dt
            applyPassiveDrift(dt: dt, excluding: [.affection])
        case .idle, .sit, .sleep:
            break
        }
    }

    private mutating func applyPassiveDrift(dt: TimeInterval, excluding skip: Set<NeedKind>) {
        if !skip.contains(.hunger) { state.needs.hunger += Self.hungerDriftPerSecond * dt }
        if !skip.contains(.thirst) { state.needs.thirst += Self.thirstDriftPerSecond * dt }
        if !skip.contains(.fun) { state.needs.fun += Self.funDriftPerSecond * dt }
        if !skip.contains(.affection) { state.needs.affection += Self.affectionDriftPerSecond * dt }
        state.needs.cleanliness += Self.cleanlinessDriftPerSecond * dt
    }

    /// Fixed run length for a momentary interaction; `nil` for the three
    /// autonomous activities, which have no protected duration.
    private static func duration(for activity: PetActivity) -> TimeInterval? {
        switch activity {
        case .eat: eatDuration
        case .drink: drinkDuration
        case .play: playDuration
        case .pet: petDuration
        case .call: callDuration
        case .idle, .sit, .sleep: nil
        }
    }
}
