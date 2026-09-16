import Foundation
import SceneKit

/// Drives the pet rig's animation state machine: preloads every base clip
/// once, resolves a requested `PetActivity` into the shortest coherent
/// sequence of clips that gets the rig from its current pose to that
/// activity's pose, and advances that sequence deterministically as
/// `update(deltaTime:)` is fed simulation time.
///
/// Only one clip is ever "active" (playing/held) per rig region at a time:
/// switching steps stops the previous step's players with a 0.25s blend-out
/// and relies on each clip's 0.25s `blendInDuration` for the crossfade in.
/// Players are attached to their target nodes exactly once, at `init`, and
/// are reused for the app's lifetime — `play`/`update` only toggle existing
/// players, never create new ones.
///
/// Two playback lanes share this one step machine:
/// - **Logical** (`play`): what `PetBehavior` says the pet is doing. Tracked
///   by `currentActivity` and `requestedTarget`, the latter surviving a
///   one-shot's visual fallback so repeated identical `play` calls (the
///   per-second UI heartbeat) stay no-ops instead of restarting anything —
///   see `play(_:careRequest:restart:)`.
/// - **Ambient** (`triggerReaction`): scoped overlays (flourishes, cursor
///   reactions, locomotion, the sleep "stir") that never touch
///   `currentActivity`/`requestedTarget` and auto-revert to whatever the
///   logical lane currently rests on. Any genuine logical `play` call
///   preempts an ambient overlay immediately (`beginStep` always stops the
///   previous players), and an ambient call rejects outright while a
///   logical multi-step route is still in flight, so the two lanes can
///   never corrupt each other's queue.
@MainActor
public final class AnimationController {
    public enum Error: Swift.Error, LocalizedError {
        case missingAssets([String])
        case clipValidationFailed(clip: String, missingNodes: [String])
        case unknownClip(String)
        case missingPostureMetadata([String])

        public var errorDescription: String? {
            switch self {
            case .missingAssets(let names):
                "Missing animation clip files: \(names.joined(separator: ", "))."
            case .clipValidationFailed(let clip, let missing):
                "Clip \(clip) targets rig nodes not present in this model: \(missing.joined(separator: ", "))."
            case .unknownClip(let name):
                "\(name) is not one of the preloaded base clips."
            case .missingPostureMetadata(let names):
                "No posture metadata for: \(names.joined(separator: ", "))."
            }
        }
    }

    /// A locomotion loop the parent can start/stop directly; SceneKit only
    /// plays the in-place cycle here, root translation lives in `SceneHost`.
    public enum Locomotion: String, Sendable {
        case walk = "shiba_walk_loop"
        case run = "shiba_run_loop"
    }

    /// One clip attached to the rig: every (node, player) pair that makes it up.
    private struct Clip {
        let name: String
        let repeats: Bool
        let duration: TimeInterval
        let players: [(node: SCNNode, key: String, player: SCNAnimationPlayer)]
    }

    /// One step of a scripted transition: which clip to play, and the posture
    /// the rig is considered to be in once that clip has started.
    private struct Step {
        let clip: String
        let posture: Posture
    }

    private enum Posture: Equatable {
        case standing, sitting, lying
    }

    /// A clip's required starting posture and the posture it leaves the rig
    /// in. Every clip's channels encode all 28 joints — including constant
    /// (unmoving) channels for joints it doesn't animate, per
    /// `blender/CLIPS_RESULT.md` — so playing a clip blends the *whole* rig
    /// to its authored pose, not just the joints it visibly moves. A clip is
    /// only safe to play as-is from a posture matching `start`; anything
    /// else needs `route(from:to:)` inserted first.
    private struct PostureRange {
        let start: Posture
        let end: Posture
        init(_ posture: Posture) { start = posture; end = posture }
        init(start: Posture, end: Posture) { self.start = start; self.end = end }
    }

    private struct ActivityProfile {
        let posture: Posture
        let mainClip: String
        /// If `mainClip` is one-shot, the activity to fall into once it finishes.
        let fallback: PetActivity?
    }

    /// The resolved logical target of the last accepted (non-redundant)
    /// `play` call, independent of whatever a one-shot's fallback is
    /// currently showing — see the type-level doc for why.
    private struct RequestTarget: Equatable {
        let mainClip: String
        let posture: Posture
    }

    /// What happens once the active (non-repeating) step's queue drains.
    private enum Completion {
        case none
        /// Existing `play`/`pet` style one-shot fallback: settles into
        /// another activity's clip via `settleVisual`, `currentActivity`
        /// unchanged.
        case activity(PetActivity)
        /// Ambient overlay finished: return to whatever clip currently
        /// represents the logical resting state (`currentRestingClip`),
        /// again without touching `currentActivity`.
        case restingClip
    }

    private static let fadeDuration: TimeInterval = 0.25
    /// Per-clip cooldown/no-repeat bookkeeping and scheduling cadence belong
    /// to `AmbientDirector`; this controller only guarantees a clip is safe
    /// to play and returns to the right place afterward.

    /// The 24 authored clips, filenames under `mac/Assets/shiba/clips/` minus
    /// the `.dae` extension, in the order listed in
    /// `docs/ANIMATION_CONTRACT.md`. `_loop` is the sole signal for whether a
    /// clip repeats, matching that contract's naming rule. Public so a
    /// preview menu and smoke tests share this one list instead of
    /// duplicating it.
    public static let clipNames = [
        "shiba_idle_loop", "shiba_sit", "shiba_sit_idle_loop", "shiba_lie_down",
        "shiba_sleep_loop", "shiba_eat_loop", "shiba_walk_loop", "shiba_run_loop",
        "shiba_bark", "shiba_fetch_pickup", "shiba_happy", "shiba_stretch",
        "shiba_stand_from_sit", "shiba_sit_from_lie", "shiba_wake", "shiba_beg_loop",
        "shiba_yawn", "shiba_scratch", "shiba_look_around_loop", "shiba_drink_loop",
        "shiba_alert", "shiba_pet_react", "shiba_shake", "shiba_fetch_carry_loop",
    ]

    /// Start/end posture for every authored clip, per `blender/CLIPS_RESULT.md`
    /// and `docs/ANIMATION_CONTRACT.md` (not the aliveness plan's pool table,
    /// which mis-listed `shiba_yawn` as sit-safe — the clip's authored entry
    /// and exit is standing/idle only).
    private static let posture: [String: PostureRange] = [
        "shiba_idle_loop": PostureRange(.standing),
        "shiba_sit": PostureRange(start: .standing, end: .sitting),
        "shiba_sit_idle_loop": PostureRange(.sitting),
        "shiba_lie_down": PostureRange(start: .sitting, end: .lying),
        "shiba_sleep_loop": PostureRange(.lying),
        "shiba_eat_loop": PostureRange(.standing),
        "shiba_walk_loop": PostureRange(.standing),
        "shiba_run_loop": PostureRange(.standing),
        "shiba_bark": PostureRange(.standing),
        "shiba_fetch_pickup": PostureRange(.standing),
        "shiba_happy": PostureRange(.standing),
        "shiba_stretch": PostureRange(start: .lying, end: .standing),
        "shiba_stand_from_sit": PostureRange(start: .sitting, end: .standing),
        "shiba_sit_from_lie": PostureRange(start: .lying, end: .sitting),
        "shiba_wake": PostureRange(start: .lying, end: .sitting),
        "shiba_beg_loop": PostureRange(.sitting),
        "shiba_yawn": PostureRange(.standing),
        "shiba_scratch": PostureRange(.sitting),
        "shiba_look_around_loop": PostureRange(.standing),
        "shiba_drink_loop": PostureRange(.standing),
        "shiba_alert": PostureRange(.standing),
        "shiba_pet_react": PostureRange(.standing),
        "shiba_shake": PostureRange(.standing),
        "shiba_fetch_carry_loop": PostureRange(.standing),
    ]

    private let root: SCNNode
    private var clips: [String: Clip] = [:]

    private var currentActivity: PetActivity = .idle
    private var currentPosture: Posture = .standing
    private var requestedTarget = RequestTarget(mainClip: "shiba_idle_loop", posture: .standing)
    private var pendingSteps: [Step] = []
    private var pendingCompletion: Completion = .none
    private var isPreviewing = false

    /// The ambient loop currently standing in for the logical activity's
    /// default resting clip (e.g. `shiba_look_around_loop` instead of
    /// `shiba_idle_loop`), set by `triggerReaction` when given a `_loop`
    /// clip. Cleared on every genuine `play` transition.
    private var restingVariantOverride: String?
    /// Consumed once by the next lying→standing route; see
    /// `preferStretchOnNextWake`.
    private var preferStretchWake = false

    private var activeStep: Step?
    private var activeElapsed: TimeInterval = 0
    private var activePlayers: [(node: SCNNode, key: String, player: SCNAnimationPlayer)] = []

    public private(set) var currentClip: String = ""
    public private(set) var isAnimating: Bool = false
    /// A locomotion loop is currently the active ambient overlay; cleared by
    /// `endLocomotion` or by any genuine `play` transition.
    public private(set) var isLocomoting: Bool = false
    /// Bumped every time a genuine (non-redundant) `play` call takes effect.
    /// `AmbientDirector` snapshots this before starting a multi-tick ambient
    /// sequence (the sleep stir, a greeting) and aborts that sequence if it
    /// changes underneath it, instead of blindly issuing the sequence's next
    /// step onto whatever the real activity transition already put on the rig.
    public private(set) var requestGeneration: Int = 0
    /// Accumulated animation clock, owned here so playback is driven off a
    /// single deterministic source instead of wall time. The caller mirrors
    /// this into `SCNSceneRenderer.sceneTime` (live `SCNView` or a headless
    /// `SCNRenderer`) every time it calls `update(deltaTime:)`, since every
    /// preloaded animation has `usesSceneTimeBase = true`.
    public private(set) var sceneTime: TimeInterval = 0

    /// Preloads and validates every clip, then attaches every channel's
    /// player to the rig. Validation happens in a read-only pass over all 24
    /// clips before any rig node is mutated: either every clip's channels
    /// resolve against `root`, or `init` throws and nothing was attached.
    public init(root: SCNNode) throws {
        self.root = root

        let missingPosture = Self.clipNames.filter { Self.posture[$0] == nil }
        guard missingPosture.isEmpty else { throw Error.missingPostureMetadata(missingPosture) }

        var parsed: [String: LoadedClip] = [:]
        var missingFiles: [String] = []
        for name in Self.clipNames {
            guard let url = AssetLocator.shibaClip(named: name) else {
                missingFiles.append(name)
                continue
            }
            do {
                parsed[name] = try AnimationLoader.load(url, name: name)
            } catch {
                missingFiles.append(name)
            }
        }
        guard missingFiles.isEmpty else { throw Error.missingAssets(missingFiles) }

        // Read-only validation pass: every channel in every clip must resolve
        // against the rig before any player is attached anywhere.
        for (name, clip) in parsed {
            let missingNodes = Set(clip.channels.map(\.nodeName))
                .filter { root.childNode(withName: $0, recursively: true) == nil }
            guard missingNodes.isEmpty else {
                throw Error.clipValidationFailed(clip: name, missingNodes: Array(missingNodes).sorted())
            }
        }

        // All clips validated: now it's safe to mutate the rig.
        for name in Self.clipNames {
            guard let loadedClip = parsed[name] else { continue }
            let repeats = name.hasSuffix("_loop")
            var built: [(node: SCNNode, key: String, player: SCNAnimationPlayer)] = []
            for (index, channel) in loadedClip.channels.enumerated() {
                // Presence already validated above.
                let target = root.childNode(withName: channel.nodeName, recursively: true)!
                let animation = channel.animation
                animation.repeatCount = repeats ? .infinity : 1
                animation.usesSceneTimeBase = true
                animation.blendInDuration = Self.fadeDuration
                animation.blendOutDuration = Self.fadeDuration
                animation.fillsForward = true
                animation.isRemovedOnCompletion = false
                let key = "\(name).\(index)"
                let player = SCNAnimationPlayer(animation: animation)
                target.addAnimationPlayer(player, forKey: key)
                player.stop() // addAnimationPlayer leaves a fresh, unpaused player running immediately
                built.append((target, key, player))
            }
            clips[name] = Clip(name: name, repeats: repeats, duration: loadedClip.duration, players: built)
        }

        // Settle into idle without going through `play`'s no-op guard.
        settleVisual(into: .idle)
    }

    /// Requests an activity. An unmet care request changes the ordinary idle
    /// visual to the authored begging loop without inventing a second logical
    /// behavior state.
    ///
    /// Idempotent by default: calling this again with the same
    /// `activity`/`careRequest` (the per-second UI heartbeat that mirrors
    /// `PetBehavior.state`) is a no-op regardless of whether a multi-step
    /// route is still in flight or a one-shot has already visually settled
    /// into its fallback — neither gets restarted. Pass `restart: true` for a
    /// genuine new user action that happens to name the same activity (e.g. a
    /// second stroke while `.pet`'s reaction is still settling), which always
    /// takes effect and replays the reaction from the top.
    public func play(_ activity: PetActivity, careRequest: Bool = false, restart: Bool = false) {
        let profile = Self.profile(for: activity, careRequest: careRequest)
        let target = RequestTarget(mainClip: profile.mainClip, posture: profile.posture)
        let isRedundantHeartbeat = !restart && !isPreviewing && currentActivity == activity && requestedTarget == target
        guard !isRedundantHeartbeat else { return }
        isPreviewing = false
        requestedTarget = target
        currentActivity = activity
        isLocomoting = false
        restingVariantOverride = nil
        requestGeneration += 1

        let useStretch = consumeStretchPreference()
        var steps = Self.route(from: currentPosture, to: profile.posture, useStretch: useStretch)
        steps.append(Step(clip: profile.mainClip, posture: profile.posture))
        pendingSteps = steps
        if let fallback = profile.fallback {
            pendingCompletion = .activity(fallback)
        } else {
            pendingCompletion = .none
        }
        beginStep(pendingSteps.removeFirst())
    }

    /// Explicit preview of any of the 24 preloaded clips, bypassing the
    /// activity state machine entirely — for QA/smoke-testing every clip in
    /// isolation. Returns the clip's duration. Does not update the tracked
    /// activity/posture (an arbitrary clip may not correspond to a coherent
    /// one), so call `play(_:)` again afterward to resume normal behavior;
    /// the next `play` call is guaranteed to take effect even if it names the
    /// same activity that was current before the preview.
    @discardableResult
    public func playClip(named name: String) throws -> TimeInterval {
        guard Self.clipNames.contains(name), let clip = clips[name] else {
            throw Error.unknownClip(name)
        }
        pendingSteps = []
        pendingCompletion = .none
        isPreviewing = true
        beginStep(Step(clip: name, posture: currentPosture))
        return clip.duration
    }

    /// Plays a single named clip as a **scoped ambient overlay**: never
    /// changes `currentActivity`/`requestedTarget`, auto-routes around a
    /// posture mismatch (e.g. `shiba_bark` — authored standing — played
    /// while begging, which is seated: stands, barks, sits back down), and
    /// either becomes the new resting loop (`clipName` is a `_loop` clip —
    /// this is how the idle/look-around base-loop swap and locomotion work)
    /// or, for a one-shot, reverts to the current resting clip when it
    /// finishes (`thenReturnToRest`, default `true`; pass `false` to hold on
    /// the clip's final frame instead, e.g. the sleep stir's own multi-step
    /// sequencing, which drives the follow-up itself).
    ///
    /// Rejects (returns `false`, no side effect) while previewing or while a
    /// logical multi-step route is still in flight, so an ambient caller can
    /// never corrupt the logical queue — callers should simply skip the tick.
    /// Uses only the players attached at `init`; never allocates a new one.
    @discardableResult
    public func triggerReaction(_ clipName: String, thenReturnToRest: Bool = true) -> Bool {
        guard isReadyForAmbient else { return false }
        guard let clip = clips[clipName], let range = Self.posture[clipName] else { return false }

        var steps: [Step] = []
        if range.start != currentPosture {
            steps += Self.route(from: currentPosture, to: range.start, useStretch: false)
        }
        steps.append(Step(clip: clipName, posture: range.end))

        if clip.repeats {
            // Becomes the new resting visual; nothing to return to.
            restingVariantOverride = clipName
            pendingCompletion = .none
        } else if thenReturnToRest {
            let restClip = currentRestingClip()
            if let restRange = Self.posture[restClip], range.end != restRange.start {
                steps += Self.route(from: range.end, to: restRange.start, useStretch: false)
            }
            pendingCompletion = .restingClip
        } else {
            pendingCompletion = .none
        }

        pendingSteps = steps
        beginStep(pendingSteps.removeFirst())
        return true
    }

    public var isReadyForAmbient: Bool {
        guard !isPreviewing, pendingSteps.isEmpty, let step = activeStep, let clip = clips[step.clip] else { return false }
        return clip.repeats || !isAnimating
    }

    /// Starts a scoped locomotion loop (auto-routing to standing first if
    /// needed, e.g. up from a seated care request). The parent/`SceneHost`
    /// should wait for `currentClip` to actually equal `gait.rawValue` before
    /// translating the root — this call may still be mid route-out.
    @discardableResult
    public func startLocomotion(_ gait: Locomotion) -> Bool {
        guard currentPosture == requestedTarget.posture else { return false }
        guard triggerReaction(gait.rawValue, thenReturnToRest: false) else { return false }
        isLocomoting = true
        return true
    }

    /// Ends locomotion and returns to the current logical resting clip,
    /// routing there if the gait left the rig in a different posture (e.g.
    /// a walk started from a seated care request lands back on `standing`;
    /// this routes back to seated before resuming `shiba_beg_loop`).
    /// No-op if locomotion isn't active.
    public func endLocomotion() {
        guard isLocomoting else { return }
        isLocomoting = false
        restingVariantOverride = nil
        guard !isPreviewing else { return }
        pendingSteps.removeAll(keepingCapacity: true)
        settleToRestingClip()
    }

    /// The authored duration of a preloaded clip, for callers (the ambient
    /// director) that need to schedule a follow-up after it plays out.
    public func duration(ofClip name: String) -> TimeInterval? {
        clips[name]?.duration
    }

    /// Makes the next lying→standing route (i.e. the next time waking up
    /// actually reaches standing) use `shiba_stretch` in one hop instead of
    /// `shiba_wake` + `shiba_stand_from_sit`. Consumed (reset) by that next
    /// route computation regardless of which posture pair it turns out to
    /// be, so a stale preference never leaks into an unrelated transition.
    public func preferStretchOnNextWake() {
        preferStretchWake = true
    }

    /// Advances the active step by `deltaTime` of simulated/animation time,
    /// and mirrors that into `sceneTime` (read this back into the renderer's
    /// `SCNSceneRenderer.sceneTime` every call). Looping steps never advance
    /// on their own. A finished one-shot step either starts the next queued
    /// step, visually settles into a fallback activity's clip or the ambient
    /// resting clip (`currentActivity`/`requestedTarget` unchanged either
    /// way — see `settleVisual`), or — with nothing queued and no completion
    /// — holds its final pose (`fillsForward`) with `isAnimating` cleared.
    public func update(deltaTime: TimeInterval) {
        guard deltaTime > 0 else { return }
        sceneTime += deltaTime
        guard let step = activeStep, let clip = clips[step.clip] else { return }
        guard !clip.repeats else { return }
        activeElapsed += deltaTime
        guard activeElapsed >= clip.duration else { return }

        if !pendingSteps.isEmpty {
            beginStep(pendingSteps.removeFirst())
            return
        }
        switch pendingCompletion {
        case .none:
            isAnimating = false
        case .activity(let fallback):
            pendingCompletion = .none
            settleVisual(into: fallback)
        case .restingClip:
            pendingCompletion = .none
            settleToRestingClip()
        }
    }

    /// Stops the previous step's players (0.25s blend-out) and starts the
    /// given step's players (0.25s blend-in, baked into each animation).
    private func beginStep(_ step: Step) {
        for entry in activePlayers {
            entry.player.stop(withBlendOutDuration: Self.fadeDuration)
        }
        guard let clip = clips[step.clip] else {
            activeStep = nil
            activePlayers = []
            isAnimating = false
            return
        }
        activeStep = step
        activeElapsed = 0
        currentPosture = step.posture
        currentClip = clip.name
        activePlayers = clip.players
        for entry in clip.players {
            entry.player.animation.startDelay = sceneTime
            entry.player.play()
        }
        isAnimating = true
    }

    /// Jumps straight to an activity's held clip with no transition route
    /// and no change to `currentActivity`/pending state. Used to settle into
    /// idle at the end of `init`, and to visually resolve a one-shot's
    /// fallback without disturbing the logically-requested activity.
    private func settleVisual(into activity: PetActivity) {
        let profile = Self.profile(for: activity, careRequest: false)
        pendingCompletion = profile.fallback.map(Completion.activity) ?? .none
        beginStep(Step(clip: profile.mainClip, posture: profile.posture))
    }

    /// What the logical lane currently rests on: the last accepted request's
    /// main clip, or the ambient override standing in for it (only while
    /// that override shares the same posture family, so a stale override
    /// from a different activity can never leak in).
    private func currentRestingClip() -> String {
        guard let variant = restingVariantOverride, let variantRange = Self.posture[variant],
              variantRange.start == requestedTarget.posture else {
            return requestedTarget.mainClip
        }
        return variant
    }

    /// Routes from wherever the rig actually is back to the resting clip's
    /// posture (a no-op route if it's already there) and plays it. Used both
    /// when an ambient one-shot's queue drains and by `endLocomotion`, so
    /// ending a scoped overlay from an unexpected posture never jump-cuts.
    private func settleToRestingClip() {
        let clip = currentRestingClip()
        guard let range = Self.posture[clip] else { return }
        var steps = Self.route(from: currentPosture, to: range.start, useStretch: false)
        steps.append(Step(clip: clip, posture: range.start))
        pendingCompletion = .none
        pendingSteps = steps
        beginStep(pendingSteps.removeFirst())
    }

    private func consumeStretchPreference() -> Bool {
        defer { preferStretchWake = false }
        return preferStretchWake
    }

    /// The posture reached at the end of an activity, and the clip that
    /// represents "being" that activity once that posture is reached.
    private static func profile(for activity: PetActivity, careRequest: Bool = false) -> ActivityProfile {
        switch activity {
        case .idle where careRequest:
            // Authored seated (`docs/ANIMATION_CONTRACT.md`), not standing.
            ActivityProfile(posture: .sitting, mainClip: "shiba_beg_loop", fallback: nil)
        case .idle:
            ActivityProfile(posture: .standing, mainClip: "shiba_idle_loop", fallback: nil)
        case .sit, .call:
            // `call` brings the pet to sit; no distinct "called" pose is authored.
            ActivityProfile(posture: .sitting, mainClip: "shiba_sit_idle_loop", fallback: nil)
        case .sleep:
            ActivityProfile(posture: .lying, mainClip: "shiba_sleep_loop", fallback: nil)
        case .eat:
            ActivityProfile(posture: .standing, mainClip: "shiba_eat_loop", fallback: nil)
        case .drink:
            ActivityProfile(posture: .standing, mainClip: "shiba_drink_loop", fallback: nil)
        case .play:
            // Momentary but held for the interaction's real (longer) duration:
            // replays the happy one-shot on itself instead of falling quiet
            // into idle after its first ~2.5s, so the whole play session
            // stays visibly happy. The per-second UI heartbeat's repeated
            // `play(.play)` calls are already no-ops (`requestedTarget`
            // unchanged), so this only ever restarts via this self-fallback.
            ActivityProfile(posture: .standing, mainClip: "shiba_happy", fallback: .play)
        case .pet:
            // Momentary: the pet-specific reaction, then fall back to idle.
            ActivityProfile(posture: .standing, mainClip: "shiba_pet_react", fallback: .idle)
        }
    }

    /// The shortest scripted path between two postures, in terms of the
    /// authored transition clips. Encodes the contract's `sit -> lie_down ->
    /// sleep` route, and its tier-2 reverse: waking chains `shiba_wake`
    /// (lying -> sitting) with `shiba_stand_from_sit` (sitting -> standing)
    /// for a full lie-to-stand, matching how each clip's own documented
    /// start/end pose chains to the next. `useStretch` swaps that lie-to-stand
    /// pair for the single-clip `shiba_stretch` route instead (both valid per
    /// the contract); ignored for every other posture pair.
    private static func route(from: Posture, to: Posture, useStretch: Bool = false) -> [Step] {
        switch (from, to) {
        case (.standing, .standing), (.sitting, .sitting), (.lying, .lying):
            []
        case (.standing, .sitting):
            [Step(clip: "shiba_sit", posture: .sitting)]
        case (.standing, .lying):
            [
                Step(clip: "shiba_sit", posture: .sitting),
                Step(clip: "shiba_lie_down", posture: .lying),
            ]
        case (.sitting, .standing):
            [Step(clip: "shiba_stand_from_sit", posture: .standing)]
        case (.sitting, .lying):
            [Step(clip: "shiba_lie_down", posture: .lying)]
        case (.lying, .standing) where useStretch:
            [Step(clip: "shiba_stretch", posture: .standing)]
        case (.lying, .standing):
            [
                Step(clip: "shiba_wake", posture: .sitting),
                Step(clip: "shiba_stand_from_sit", posture: .standing),
            ]
        case (.lying, .sitting):
            [Step(clip: "shiba_wake", posture: .sitting)]
        }
    }
}
