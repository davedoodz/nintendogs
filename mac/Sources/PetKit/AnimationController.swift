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
@MainActor
public final class AnimationController {
    public enum Error: Swift.Error, LocalizedError {
        case missingAssets([String])
        case clipValidationFailed(clip: String, missingNodes: [String])
        case unknownClip(String)

        public var errorDescription: String? {
            switch self {
            case .missingAssets(let names):
                "Missing animation clip files: \(names.joined(separator: ", "))."
            case .clipValidationFailed(let clip, let missing):
                "Clip \(clip) targets rig nodes not present in this model: \(missing.joined(separator: ", "))."
            case .unknownClip(let name):
                "\(name) is not one of the preloaded base clips."
            }
        }
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

    private enum Posture {
        case standing, sitting, lying
    }

    private struct ActivityProfile {
        let posture: Posture
        let mainClip: String
        /// If `mainClip` is one-shot, the activity to fall into once it finishes.
        let fallback: PetActivity?
    }

    private static let fadeDuration: TimeInterval = 0.25

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

    private let root: SCNNode
    private var clips: [String: Clip] = [:]

    private var currentActivity: PetActivity = .idle
    private var currentPosture: Posture = .standing
    private var pendingSteps: [Step] = []
    private var pendingFallback: PetActivity?
    private var isPreviewing = false

    private var activeStep: Step?
    private var activeElapsed: TimeInterval = 0
    private var activePlayers: [(node: SCNNode, key: String, player: SCNAnimationPlayer)] = []

    public private(set) var currentClip: String = ""
    public private(set) var isAnimating: Bool = false
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
    public func play(_ activity: PetActivity, careRequest: Bool = false) {
        let profile = Self.profile(for: activity, careRequest: careRequest)
        let isAlreadyShowingRequestedVisual = currentClip == profile.mainClip
        guard activity != currentActivity || isPreviewing || isAlreadyShowingRequestedVisual == false else { return }
        isPreviewing = false
        currentActivity = activity
        var steps = Self.route(from: currentPosture, to: profile.posture)
        steps.append(Step(clip: profile.mainClip, posture: profile.posture))
        pendingSteps = steps
        pendingFallback = profile.fallback
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
        pendingFallback = nil
        isPreviewing = true
        beginStep(Step(clip: name, posture: currentPosture))
        return clip.duration
    }

    /// Advances the active step by `deltaTime` of simulated/animation time,
    /// and mirrors that into `sceneTime` (read this back into the renderer's
    /// `SCNSceneRenderer.sceneTime` every call). Looping steps never advance
    /// on their own. A finished one-shot step either starts the next queued
    /// step, visually settles into a fallback activity's clip (`play`/`pet`
    /// settle into idle's clip once their one-shot finishes, without
    /// changing `currentActivity` — see `settleVisual`), or — with nothing
    /// queued and no fallback — holds its final pose (`fillsForward`) with
    /// `isAnimating` cleared.
    public func update(deltaTime: TimeInterval) {
        guard deltaTime > 0 else { return }
        sceneTime += deltaTime
        guard let step = activeStep, let clip = clips[step.clip] else { return }
        guard !clip.repeats else { return }
        activeElapsed += deltaTime
        guard activeElapsed >= clip.duration else { return }

        if !pendingSteps.isEmpty {
            beginStep(pendingSteps.removeFirst())
        } else if let fallback = pendingFallback {
            // Visual settle only: keep `currentActivity` as whatever was
            // actually requested (e.g. `.play`/`.pet`) so the care loop's
            // repeated same-activity `play()` calls stay no-ops instead of
            // re-triggering the one-shot on every tick for the rest of the
            // interaction's duration.
            pendingFallback = nil
            settleVisual(into: fallback)
        } else {
            isAnimating = false
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
        beginStep(Step(clip: profile.mainClip, posture: profile.posture))
    }

    /// The posture reached at the end of an activity, and the clip that
    /// represents "being" that activity once that posture is reached.
    private static func profile(for activity: PetActivity, careRequest: Bool = false) -> ActivityProfile {
        switch activity {
        case .idle where careRequest:
            ActivityProfile(posture: .standing, mainClip: "shiba_beg_loop", fallback: nil)
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
            // Momentary: play the happy one-shot, then fall back to idle.
            ActivityProfile(posture: .standing, mainClip: "shiba_happy", fallback: .idle)
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
    /// start/end pose chains to the next.
    private static func route(from: Posture, to: Posture) -> [Step] {
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
