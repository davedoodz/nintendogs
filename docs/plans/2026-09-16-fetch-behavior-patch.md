# Deferred patch: `PetActivity.fetch` + `PetBehavior` fetch duration + `AnimationController.profile(for: .fetch)`

Not applied — `mac/Sources/PetKit/Needs.swift`, `Behavior.swift`, `AnimationController.swift`,
and `mac/Tests/PetKitTests/BehaviorTests.swift` are owned by the concurrent wander/presence
session in this worktree. Apply against the **current** content of those files (they already
carry `lastInteractionAt`/`awakeUntil`/`isInteracting` from that session — this patch does not
touch any of it).

`FetchSequence.swift` and `FetchSequenceTests.swift` are already landed and independently
verified (see final report). Everything below is additive to the four files above.

## 1. `mac/Sources/PetKit/Needs.swift`

Add `fetch` to `PetActivity` (currently `case idle, sit, sleep, eat, drink, play, call, pet`):

```swift
public enum PetActivity: String, Codable, Sendable, CaseIterable, Equatable {
    case idle, sit, sleep, eat, drink, play, call, pet, fetch
}
```

No other change needed in this file — `PetState.careRequest` already guards on
`activity == .idle || activity == .sit`, so it's already `nil` during `.fetch`; no edit required
there, just worth a regression test (see §4).

## 2. `mac/Sources/PetKit/Behavior.swift`

### 2a. Track the *actual* duration behind the current interaction (needed because fetch's
duration is per-throw distance, not a fixed constant like `eat`/`drink`/`play`/`pet`/`call`).

Add a stored property next to `interactionEndsAt`:

```swift
private var interactionEndsAt: Date?
private var interactionDuration: TimeInterval?   // NEW — total length of the running interaction, for rate-based math (fetch)
```

### 2b. Split `interact(_:at:)` into a public entry point that looks up the fixed table, plus a
new public overload that takes an explicit duration (used by fetch's caller with
`FetchSequence.totalDuration`), both funneling into one private `perform`:

```swift
public mutating func interact(_ activity: PetActivity, at date: Date) {
    perform(activity, at: date, duration: Self.duration(for: activity))
}

/// For interactions whose length isn't a fixed constant — currently only `.fetch`, whose
/// duration is the just-computed `FetchSequence.totalDuration` for this throw.
public mutating func interact(_ activity: PetActivity, at date: Date, duration: TimeInterval) {
    perform(activity, at: date, duration: duration)
}

private mutating func perform(_ activity: PetActivity, at date: Date, duration: TimeInterval?) {
    guard date >= state.lastUpdated else { return }
    tick(at: date, calendar: .current)
    manualRestUntil = activity == .sleep ? date.addingTimeInterval(15 * 60) : nil
    state.lastInteractionAt = date
    awakeUntil = activity == .sleep ? nil : date.addingTimeInterval(60)
    state.activity = activity
    interactionEndsAt = duration.map { date.addingTimeInterval($0) }
    interactionDuration = duration
}
```

(This replaces the existing body of `interact(_:at:)` — same behavior for every existing
caller/activity, verbatim, just routed through `perform`.)

### 2c. Reset `interactionDuration` wherever `interactionEndsAt` is cleared, in `step(dt:at:calendar:)`:

```swift
if cursor >= endsAt {
    interactionEndsAt = nil
    interactionDuration = nil   // NEW
    let night = Self.isNight(cursor, calendar: calendar)
    state.activity = autonomousActivity(at: cursor, night: night)
    applyAutonomous(state.activity, dt: dt - interactionTime)
}
```

### 2d. `applyInteraction` gains a `.fetch` case — R12: `+100 fun`, `+20 affection` linearly over
the *actual* fetch duration (not a fixed constant, since it varies by throw distance), plus the
same combined energy drain `.play` uses ("awake-play energy drain"):

```swift
case .fetch:
    let duration = max(interactionDuration ?? 0, .ulpOfOne)
    state.needs.fun += (100.0 / duration) * dt
    state.needs.affection += (20.0 / duration) * dt
    state.needs.energy -= (Self.energyAwakeDrainPerSecond + Self.energyPlayExtraDrainPerSecond) * dt
    applyPassiveDrift(dt: dt, excluding: [.fun, .affection])
```

Add this case alongside the existing `.eat`/`.drink`/`.play`/`.pet`/`.call`/`.idle,.sit,.sleep`
cases in the same switch (exhaustiveness will force it once `.fetch` exists).

### 2e. `applyAutonomous`'s switch also needs `.fetch` added to its energy-drain case list (it's
only reached if `.fetch` were ever the *autonomous* activity, which it never is — `.fetch` is only
entered via `interact`, same as `.play`/`.pet`/`.call` — but the switch must stay exhaustive):

```swift
case .idle, .eat, .drink, .play, .call, .pet, .fetch:
    state.needs.energy -= Self.energyAwakeDrainPerSecond * dt
```

### 2f. `init(state:)` — a persisted `.fetch` activity must not resume after a relaunch (a fetch's
remaining duration/position isn't persisted). Today this reset is driven by
`Self.duration(for: normalized.activity) != nil`, but `duration(for:)` is the *fixed-table*
lookup and `.fetch` has no fixed entry (its duration is per-throw). Replace the momentary-check
with a dedicated predicate so `.fetch` is included:

```swift
private static func isMomentary(_ activity: PetActivity) -> Bool {
    switch activity {
    case .eat, .drink, .play, .pet, .call, .fetch: true
    case .idle, .sit, .sleep: false
    }
}
```

And in `init`:

```swift
if Self.isMomentary(normalized.activity) {
    normalized.activity = .idle
}
```

(replaces `if Self.duration(for: normalized.activity) != nil {`).

### 2g. `duration(for:)` — must stay exhaustive; give `.fetch` a `nil` (it never has a fixed
duration, callers always use the explicit-duration overload):

```swift
private static func duration(for activity: PetActivity) -> TimeInterval? {
    switch activity {
    case .eat: eatDuration
    case .drink: drinkDuration
    case .play: playDuration
    case .pet: petDuration
    case .call: callDuration
    case .idle, .sit, .sleep, .fetch: nil
    }
}
```

### 2h. R11 cancellation — already works, no code change. `interact(_:at:)` unconditionally
overwrites `state.activity` and recomputes `interactionEndsAt`/`interactionDuration` regardless
of what was running before, so calling `interact(.pet, at:)` (or any other activity) while
`state.activity == .fetch` immediately ends the fetch and starts the new interaction — exactly
R11's "any other interaction during a fetch cancels it." Worth a regression test (§4) since
nothing pins this today.

### 2i. Doc header (lines 18-23) — extend the rates list to mention fetch, e.g. append to the
momentary-interactions bullet:

```
///   `eat` 10s (hunger), `drink` 6s (thirst), `play` 12s (+100 fun, +20 affection),
///   `pet` 5s (+100 affection, +10 fun), `call` 2s (+5 affection, wakes from sleep),
///   `fetch` (duration varies by throw distance; +100 fun, +20 affection, plus play's
///   extra awake energy drain — see `FetchSequence`).
```

## 3. `mac/Sources/PetKit/AnimationController.swift`

`profile(for:careRequest:)`'s switch must become exhaustive once `.fetch` exists. The app drives
fetch's clips directly via `playClip(named:)` per phase (see plan KTD5/U6), so this case is never
actually shown — it only needs to compile and be harmless if ever hit. Add right after `.pet`:

```swift
case .fetch:
    // Fetch bypasses this mapping entirely — the app calls `playClip(named:)` per
    // `FetchSequence.clip` and `play(.idle)` at `.done`. This case only exists to keep
    // the switch exhaustive; the idle profile is a safe default if it's ever reached.
    ActivityProfile(posture: .standing, mainClip: "shiba_idle_loop", fallback: nil)
```

## 4. `mac/Tests/PetKitTests/BehaviorTests.swift` — suggested additions (not applied)

```swift
@Test func fetchAppliesFunAndAffectionLinearlyOverItsActualDuration() {
    var behavior = PetBehavior(state: PetState(
        needs: PetNeeds(fun: 20, affection: 20),
        activity: .idle,
        lastUpdated: date(2026, 1, 1, 12)
    ))
    let start = date(2026, 1, 1, 12)
    behavior.interact(.fetch, at: start, duration: 8) // e.g. FetchSequence.totalDuration for some throw
    behavior.tick(at: start.addingTimeInterval(8), calendar: utc)
    #expect(abs(behavior.state.needs.fun - 120) < 1e-6, "a full fetch should raise fun by exactly 100")
    #expect(abs(behavior.state.needs.affection - 40) < 1e-6, "a full fetch should raise affection by exactly 20")
}

@Test func pettingDuringAFetchCancelsIt() {
    var behavior = PetBehavior(state: PetState(activity: .idle, lastUpdated: date(2026, 1, 1, 12)))
    let start = date(2026, 1, 1, 12)
    behavior.interact(.fetch, at: start, duration: 10)
    #expect(behavior.state.activity == .fetch)
    behavior.interact(.pet, at: start.addingTimeInterval(2))
    #expect(behavior.state.activity == .pet, "petting mid-fetch should replace it, not queue behind it")
}

@Test func careRequestStaysNilDuringFetch() {
    var behavior = PetBehavior(state: PetState(needs: PetNeeds(hunger: 90), activity: .idle, lastUpdated: date(2026, 1, 1, 12)))
    behavior.interact(.fetch, at: date(2026, 1, 1, 12), duration: 6)
    #expect(behavior.state.careRequest == nil, "no care request while fetching")
}
```

## Verification already done for this patch (paper only — not run against real files)

Hand-traced against the current file contents read during this session: `perform`'s body is a
verbatim carry of today's `interact(_:at:)` body (including the wander session's
`state.lastInteractionAt = date` / `awakeUntil` lines), so no behavior changes for
eat/drink/play/pet/call/idle/sit/sleep. Only additive: the `duration:` overload, the `.fetch`
switch arms, and `interactionDuration` bookkeeping.
