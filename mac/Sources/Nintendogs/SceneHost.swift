import SceneKit
import AppKit
import PetKit

/// Transparent SceneKit view with the DS-style fixed camera (KTD4), warm light and a blob shadow.
final class SceneHost: SCNView {
    static let dogHeight: CGFloat = 1.0
    /// Camera values ported from the web study (`src/scene.js`), rescaled for a 1-unit dog.
    private static let cameraPosition = SCNVector3(0, 0.78, 2.3)
    private static let cameraLook = SCNVector3(0, 0.48, 0)

    /// Depth band wander targets are picked within, either side of the
    /// camera's look-at plane (`docs/ALIVENESS_PLAN.md` Phase 2: "z within
    /// ±0.15 of camera plane").
    private static let wanderZRange: ClosedRange<CGFloat> = -0.15...0.15
    /// Radius of the normalized pet, including a small allowance for moving paws.
    private var petRadius: CGFloat = 0
    /// A requested run only actually runs if the picked target is at least
    /// this fraction of the walkable width away (`docs/ALIVENESS_PLAN.md`
    /// Phase 2: "run_loop when ... the target is > 60% of panel width away").
    private static let runDistanceFraction: CGFloat = 0.6
    /// Distance at which a wander leg counts as arrived (~3% of dog height).
    private static let arrivalDistance: CGFloat = 0.03
    /// Facing/gaze easing time constants (`docs/ALIVENESS_PLAN.md` Phase 2:
    /// "0.3 s eased" yaw; Phase 3: "spring-eased" gaze).
    private static let facingEaseTau: TimeInterval = 0.3
    private static let gazeEaseTau: TimeInterval = 0.25
    /// Additive head-gaze caps (`docs/ALIVENESS_PLAN.md` Phase 3;
    /// `docs/ANIMATION_CONTRACT.md` rigid-skinning rule: `head` is distal to
    /// the seam-limited `neck` joint, so it tolerates more than the ~7-10°
    /// body-adjacent limit — same order as the accepted `tail2` ±20° yaw).
    private static let maxGazeYaw: CGFloat = 20 * .pi / 180
    private static let maxGazePitch: CGFloat = 10 * .pi / 180
    /// "Nearby" hover/gaze zone (`docs/ALIVENESS_PLAN.md` Phase 3: "cursor is
    /// within ~1.5 panel-widths") — expanding each side by a quarter width
    /// yields a total span of 1.5x the view.
    private static let nearbyZoneExpansion: CGFloat = 0.25

    private let petAnchor = SCNNode()
    private let blobShadow = SCNNode()
    private var petClickPoint: CGPoint?
    var onCall: (() -> Void)?
    var onStroke: (() -> Void)?
    var onPlay: (() -> Void)?
    private var stroked = false
    private var lastStrokeTime: TimeInterval = 0
    private let bowl = SCNNode()
    private let bowlContents = SCNNode()
    private var displayedActivity: PetActivity?

    // MARK: Wander / root motion

    /// Master on/off switch (e.g. a debug/personality menu toggle). Setting
    /// this to `false` also cancels any in-progress wander.
    var wanderEnabled = true {
        didSet { if !wanderEnabled { stopWander() } }
    }
    private(set) var isWandering = false
    /// The gait actually in effect for the current wander leg — may differ
    /// from a requested run if the picked target turned out too close to
    /// justify one; check this after `startWander` to see which was chosen.
    private(set) var isRunning = false
    private var wanderTarget: SCNVector3?
    private var gaitSpeeds: (walk: CGFloat, run: CGFloat)?

    // MARK: Gaze

    private weak var headNode: SCNNode?
    private var gazeYaw: CGFloat = 0
    private var gazePitch: CGFloat = 0
    private let gazeOffset = SCNNode()

    // MARK: Cursor presence

    private(set) var cursorNearby = false
    private(set) var cursorAttention = false

    /// Root position/facing for external bounds/behavior assertions
    /// (headless proof, tests). `presentation` so a caller reading these
    /// between `updatePresence` calls sees the actually-rendered pose,
    /// including any in-flight `showCare` approach action.
    var petPosition: SCNVector3 { petAnchor.presentation.position }
    var petFacing: CGFloat { petAnchor.presentation.eulerAngles.y }

    override init(frame: NSRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        configure()
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func configure() {
        let scene = SCNScene()
        scene.background.contents = nil
        self.scene = scene
        backgroundColor = .clear
        allowsCameraControl = false
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 30
        setAnimationActive(false)    // render on demand until animation exists (idle CPU budget)

        let camera = SCNCamera()
        camera.fieldOfView = 38
        camera.zNear = 0.05
        camera.zFar = 40
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = Self.cameraPosition
        cameraNode.look(at: Self.cameraLook)
        scene.rootNode.addChildNode(cameraNode)
        // Explicit rather than relying on SCNView's "first camera" fallback:
        // a headless SCNRenderer sharing this scene needs pointOfView set.
        pointOfView = cameraNode

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = NSColor(calibratedRed: 0.82, green: 0.78, blue: 0.70, alpha: 1)
        ambient.light?.intensity = 900
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.86, alpha: 1)
        sun.light?.intensity = 800
        sun.light?.castsShadow = false   // shadow maps halo on a transparent window; blob shadow instead
        sun.eulerAngles = SCNVector3(-0.9, 0.6, 0)
        scene.rootNode.addChildNode(sun)

        blobShadow.geometry = SCNPlane(width: 0.9, height: 0.6)
        let shadowMaterial = SCNMaterial()
        shadowMaterial.diffuse.contents = Self.blobShadowImage()
        shadowMaterial.lightingModel = .constant
        shadowMaterial.isDoubleSided = true
        shadowMaterial.writesToDepthBuffer = false
        blobShadow.geometry?.materials = [shadowMaterial]
        blobShadow.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        blobShadow.position = SCNVector3(0, 0.002, 0)
        scene.rootNode.addChildNode(blobShadow)

        scene.rootNode.addChildNode(petAnchor)
        let rim = SCNTorus(ringRadius: 0.13, pipeRadius: 0.025)
        rim.firstMaterial?.diffuse.contents = NSColor.systemOrange
        bowl.geometry = rim
        bowl.position = SCNVector3(0, 0.04, 0.55)
        let contents = SCNCylinder(radius: 0.12, height: 0.02)
        bowlContents.geometry = contents
        bowl.addChildNode(bowlContents)
        bowl.isHidden = true
        scene.rootNode.addChildNode(bowl)
    }

    func setPet(_ node: SCNNode, rawHeight: CGFloat) throws {
        guard let walk = AssetLocator.shibaClip(named: "shiba_walk_loop"),
              let run = AssetLocator.shibaClip(named: "shiba_run_loop") else {
            throw AssetLocator.MissingAsset(message: "Walking and running clips are required.")
        }
        gaitSpeeds = try (
            GaitStride.speed(clip: walk, scale: Self.dogHeight / rawHeight),
            GaitStride.speed(clip: run, scale: Self.dogHeight / rawHeight)
        )
        petAnchor.childNodes.forEach { $0.removeFromParentNode() }
        petAnchor.addChildNode(node)
        petAnchor.eulerAngles.y = 0 // Authored head/mouth extend toward +Z, toward the camera.
        let (minimum, maximum) = node.boundingBox
        let x = max(abs(minimum.x), abs(maximum.x))
        let z = max(abs(minimum.z), abs(maximum.z))
        petRadius = hypot(x, z) + 0.06
        headNode = node.childNode(withName: "head", recursively: true)
        attachGazeConstraint()
        setNeedsDisplay(bounds)
    }

    func setAnimationActive(_ active: Bool) {
        guard isPlaying != active || rendersContinuously != active else { return }
        isPlaying = active
        rendersContinuously = active
    }

    /// Spin the pet a quarter turn; used from the menu while the rip's facing is being confirmed.
    func rotatePet() {
        petAnchor.eulerAngles.y += .pi / 2
        setNeedsDisplay(bounds)
    }

    func showCare(activity: PetActivity, needs: PetNeeds) {
        let caring = activity == .eat || activity == .drink
        if displayedActivity != activity {
            displayedActivity = activity
            if caring || activity == .call {
                // Only these two ever need to reposition the root; every
                // other activity (idle/sit/sleep/play/pet) leaves the pet
                // exactly where it is, so a wandered-to spot survives the
                // ~1s behavior refresh that calls this on every tick.
                stopWander()
                petAnchor.removeAction(forKey: "approach")
                let destination = SCNVector3(0, 0, activity == .call ? 0.3 : 0)
                petAnchor.runAction(.move(to: destination, duration: 0.8), forKey: "approach")
            }
        }
        bowl.isHidden = !caring
        if caring {
            bowlContents.geometry?.firstMaterial?.diffuse.contents =
                activity == .drink ? NSColor.systemBlue : NSColor.brown
            let deficit = activity == .drink ? needs.thirst : needs.hunger
            bowlContents.scale = SCNVector3(1, max(0.05, deficit / 100), 1)
            petAnchor.eulerAngles.y = 0
        } else if activity == .call {
            petAnchor.eulerAngles.y = 0
        }
    }

    // MARK: - Presence: wander, gaze, cursor, shadow

    /// Advances root motion, head gaze and cursor state by `deltaTime`.
    /// Called every tick from the app's loop.
    ///
    /// - `wandering`: gates whether an in-progress wander actually moves the
    ///   root this call. `false` *pauses* motion — the target and gait are
    ///   kept, not discarded — so a caller that calls `startWander` before
    ///   its controller has actually reached a walk/run clip can pass
    ///   `false` until it has, then `true`, without losing or re-rolling the
    ///   target. Call `stopWander()` to actually cancel.
    /// - `cursorOverride`: a view-space point to use as the cursor position
    ///   instead of polling `NSEvent.mouseLocation` — lets a headless caller
    ///   (sharing this view's scene/camera with an off-screen renderer, no
    ///   real pointer) drive gaze/hover deterministically.
    func updatePresence(
        deltaTime: TimeInterval,
        activity: PetActivity,
        wandering: Bool,
        cursorOverride: CGPoint? = nil
    ) {
        guard deltaTime > 0 else { return }
        clampToWalkableBounds()
        if isWandering, wandering, wanderEnabled {
            stepWander(deltaTime: deltaTime)
        }
        let viewPoint = cursorViewPoint(override: cursorOverride)
        updateCursorState(viewPoint: viewPoint)
        updateGaze(deltaTime: deltaTime, activity: activity, viewPoint: viewPoint)
        blobShadow.position = SCNVector3(petAnchor.position.x, blobShadow.position.y, petAnchor.position.z)
    }

    /// Picks a wander target — the bowl, or a random point within the
    /// current walkable bounds — and commits to a gait for it. A requested
    /// run downgrades to a walk if the target turns out too close to justify
    /// running; check `isRunning` afterward to see which was actually
    /// chosen. No motion happens until `updatePresence(wandering: true, …)`.
    func startWander(running: Bool, towardBowl: Bool) {
        guard wanderEnabled, gaitSpeeds != nil else { return }
        let target: SCNVector3 = towardBowl
            ? SCNVector3(bowl.position.x, petAnchor.position.y, bowl.position.z)
            : randomWanderTarget()
        let dx = Double(target.x - petAnchor.position.x)
        let dz = Double(target.z - petAnchor.position.z)
        let distance = CGFloat(hypot(dx, dz))
        let range = walkableXRange(atWorldZ: target.z)
        let runThreshold = (range.upperBound - range.lowerBound) * Self.runDistanceFraction
        wanderTarget = target
        isWandering = true
        isRunning = running && distance >= runThreshold
    }

    /// Hard-cancels any in-progress or pending wander: clears the target and
    /// gait, and stops root translation immediately. Call on interactions,
    /// care, or any other suppression — safe to call at any time, including
    /// when not wandering.
    func stopWander() {
        wanderTarget = nil
        isWandering = false
        isRunning = false
    }

    private func stepWander(deltaTime: TimeInterval) {
        guard var target = wanderTarget else { return }
        // Re-clamp every step, not just the initial pick, so a resize mid-walk
        // corrects the target smoothly instead of fighting the root's own
        // defensive clamp in `clampToWalkableBounds` a moment later.
        let range = walkableXRange(atWorldZ: target.z)
        if range.lowerBound <= range.upperBound {
            target.x = min(max(target.x, range.lowerBound), range.upperBound)
            wanderTarget = target
        }

        let dx = Double(target.x - petAnchor.position.x)
        let dz = Double(target.z - petAnchor.position.z)
        let distance = hypot(dx, dz)
        guard distance > Double(Self.arrivalDistance) else {
            wanderTarget = nil
            isWandering = false
            isRunning = false
            return
        }

        guard let gaitSpeeds else { return }
        let speed = isRunning ? gaitSpeeds.run : gaitSpeeds.walk
        let travel = min(Double(speed) * deltaTime, distance)
        let dirX = dx / distance
        let dirZ = dz / distance
        petAnchor.position.x += CGFloat(dirX * travel)
        petAnchor.position.z += CGFloat(dirZ * travel)

        // The loaded rig faces +Z (measured head and mouth world positions).
        let desiredYaw = atan2(dirX, dirZ)
        let easedYaw = easedAngle(
            current: Double(petAnchor.eulerAngles.y),
            target: desiredYaw,
            tau: Self.facingEaseTau,
            deltaTime: deltaTime
        )
        petAnchor.eulerAngles.y = CGFloat(easedYaw)
    }

    private func randomWanderTarget() -> SCNVector3 {
        let z = CGFloat.random(in: Self.wanderZRange)
        let range = walkableXRange(atWorldZ: z)
        let x = range.lowerBound <= range.upperBound ? CGFloat.random(in: range) : 0
        return SCNVector3(x, petAnchor.position.y, z)
    }

    /// The visible X range at a given world Z and the current view size,
    /// inset so the dog's body does not clip the window edge. Recomputed
    /// from `bounds`/the live camera every call, so it always reflects the
    /// current panel size (resize-safe).
    private func walkableXRange(atWorldZ z: CGFloat) -> ClosedRange<CGFloat> {
        guard bounds.width > 0, bounds.height > 0 else { return 0...0 }
        // Use the upper body's near depth so the footprint includes perspective.
        let depth = projectPoint(SCNVector3(0, Self.dogHeight, z + 0.15)).z
        let left = unprojectPoint(SCNVector3(bounds.minX, bounds.midY, depth))
        let right = unprojectPoint(SCNVector3(bounds.maxX, bounds.midY, depth))
        let lo = min(left.x, right.x) + petRadius
        let hi = max(left.x, right.x) - petRadius
        return lo <= hi ? lo...hi : 0...0
    }

    /// Defensive resize handling: pulls the root back inside the current
    /// walkable X range if a shrink left it outside. Skipped while
    /// `showCare`'s "approach" action owns root position (call/eat/drink),
    /// so it never fights that motion.
    private func clampToWalkableBounds() {
        guard petAnchor.action(forKey: "approach") == nil else { return }
        let range = walkableXRange(atWorldZ: petAnchor.position.z)
        guard range.lowerBound <= range.upperBound else { return }
        let clamped = min(max(petAnchor.position.x, range.lowerBound), range.upperBound)
        if clamped != petAnchor.position.x {
            petAnchor.position.x = clamped
        }
    }

    // MARK: - Gaze

    /// Attaches the additive head-aim constraint once a rig is set. Uses
    /// `SCNTransformConstraint`, which SceneKit resolves after that frame's
    /// animation/skinning-driving transforms are already applied — composing
    /// on top of whatever the current clip pose is, never overwriting an
    /// authored bone value directly (the rigid-skinning rule in
    /// `docs/ANIMATION_CONTRACT.md` still holds: no bone is re-targeted).
    private func attachGazeConstraint() {
        guard let head = headNode else { return }
        let offset = gazeOffset
        let constraint = SCNTransformConstraint(inWorldSpace: true) { _, transform in
            // The render callback reads SceneKit-owned state, not mutable view fields.
            let angles = offset.eulerAngles
            let yaw = SCNMatrix4MakeRotation(angles.y, 0, 1, 0)
            let pitch = SCNMatrix4MakeRotation(-angles.x, cos(angles.z), 0, -sin(angles.z))
            var result = SCNMatrix4Mult(transform, SCNMatrix4Mult(yaw, pitch))
            // Rotate orientation about the head joint, never its position.
            result.m41 = transform.m41
            result.m42 = transform.m42
            result.m43 = transform.m43
            return result
        }
        head.constraints = [constraint]
    }

    private func updateGaze(deltaTime: TimeInterval, activity: PetActivity, viewPoint: CGPoint?) {
        let suppressed = activity == .eat || activity == .drink || activity == .sleep
        var targetYaw: CGFloat = 0
        var targetPitch: CGFloat = 0
        if !suppressed, cursorNearby, let viewPoint, let head = headNode,
           let aim = gazeAim(for: viewPoint, head: head) {
            targetYaw = aim.yaw
            targetPitch = aim.pitch
        }
        gazeYaw = CGFloat(easedAngle(
            current: Double(gazeYaw), target: Double(targetYaw), tau: Self.gazeEaseTau, deltaTime: deltaTime
        ))
        gazePitch = CGFloat(easedAngle(
            current: Double(gazePitch), target: Double(targetPitch), tau: Self.gazeEaseTau, deltaTime: deltaTime
        ))
        gazeOffset.eulerAngles = SCNVector3(gazePitch, gazeYaw, petAnchor.eulerAngles.y)
    }

    /// Aims at the cursor unprojected to a point at the pet's current depth
    /// (`docs/ALIVENESS_PLAN.md` Phase 3: "Convert to a point at dog depth"),
    /// expressed as a yaw relative to the body's current facing (so it adds
    /// to, rather than fights, wander facing) and a pitch from horizontal.
    /// Both are capped to the additive gaze limits. Uses model-space
    /// `petAnchor` values (authoritative within this same call, unlike
    /// `presentation` which can lag a render) for the reference frame, and
    /// `head.presentation` for the head's own animated world position, since
    /// only `presentation` reflects the running clip's current pose.
    private func gazeAim(for viewPoint: CGPoint, head: SCNNode) -> (yaw: CGFloat, pitch: CGFloat)? {
        let headWorld = head.presentation.worldPosition
        let depthZ = headWorld.z + 0.8
        let near = unprojectPoint(SCNVector3(viewPoint.x, viewPoint.y, 0))
        let far = unprojectPoint(SCNVector3(viewPoint.x, viewPoint.y, 1))
        let rayZ = far.z - near.z
        guard abs(rayZ) > 0.0001 else { return nil }
        let t = (depthZ - near.z) / rayZ
        let targetWorld = SCNVector3(near.x + (far.x - near.x) * t, near.y + (far.y - near.y) * t, depthZ)

        let dx = Double(targetWorld.x - headWorld.x)
        let dy = Double(targetWorld.y - headWorld.y)
        let dz = Double(targetWorld.z - headWorld.z)
        let horizontal = hypot(dx, dz)
        guard horizontal > 0.0001 else { return nil }

        let desiredWorldYaw = atan2(dx, dz)
        let bodyYaw = Double(petAnchor.eulerAngles.y)
        let relativeYaw = normalizedAngle(desiredWorldYaw - bodyYaw)
        // Positive target pitch means up; the world-space constraint applies -X rotation.
        let pitch = atan2(dy, horizontal)
        return (
            yaw: CGFloat(relativeYaw).clamped(to: -Self.maxGazeYaw...Self.maxGazeYaw),
            pitch: CGFloat(pitch).clamped(to: -Self.maxGazePitch...Self.maxGazePitch)
        )
    }

    // MARK: - Cursor presence

    /// `NSEvent.mouseLocation` is a static, global-screen-coordinate query —
    /// unlike a global event monitor it needs no Accessibility permission and
    /// does not require this panel to be key/focused. Polled once per
    /// `updatePresence` call rather than via an event monitor, matching the
    /// panel's non-activating design.
    private func cursorViewPoint(override: CGPoint?) -> CGPoint? {
        if let override { return override }
        guard let window else { return nil }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return convert(windowPoint, from: nil)
    }

    private func updateCursorState(viewPoint: CGPoint?) {
        guard let viewPoint else {
            cursorNearby = false
            cursorAttention = false
            return
        }
        let nearbyZone = bounds.insetBy(
            dx: -bounds.width * Self.nearbyZoneExpansion,
            dy: -bounds.height * Self.nearbyZoneExpansion
        )
        cursorNearby = nearbyZone.contains(viewPoint)
        guard bounds.contains(viewPoint) else {
            cursorAttention = false
            return
        }
        let hit = hitTest(viewPoint, options: [SCNHitTestOption.firstFoundOnly: true])
        cursorAttention = hit.first.map { isPetNode($0.node) } ?? false
    }

    // MARK: - Mouse: click (call), drag (stroke), double-click (play)

    override func mouseDown(with event: NSEvent) {
        stroked = false
        let point = convert(event.locationInWindow, from: nil)
        let hit = hitTest(point, options: [SCNHitTestOption.firstFoundOnly: true])
        if let node = hit.first?.node, isPetNode(node) {
            petClickPoint = point
            return
        }
        petClickPoint = nil
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = petClickPoint else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) >= 8 else { return }
        stroked = true
        let hit = hitTest(point, options: [.firstFoundOnly: true])
        guard let node = hit.first?.node, isPetNode(node) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastStrokeTime >= 1 {
            lastStrokeTime = now
            onStroke?()
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { petClickPoint = nil }
        guard let start = petClickPoint else {
            super.mouseUp(with: event)
            return
        }
        let end = convert(event.locationInWindow, from: nil)
        let distance = hypot(end.x - start.x, end.y - start.y)
        guard !stroked, distance < 8 else { return }
        if event.clickCount >= 2 {
            onPlay?()
        } else {
            onCall?()
        }
    }

    private func isPetNode(_ node: SCNNode) -> Bool {
        var current: SCNNode? = node
        while let candidate = current {
            if candidate === petAnchor { return true }
            current = candidate.parent
        }
        return false
    }

    private static func blobShadowImage() -> NSImage {
        let size = NSSize(width: 128, height: 128)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colorsAndLocations:
            (NSColor(white: 0, alpha: 0.38), 0.0),
            (NSColor(white: 0, alpha: 0.18), 0.55),
            (NSColor(white: 0, alpha: 0.0), 1.0))
        gradient?.draw(in: NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)), relativeCenterPosition: .zero)
        image.unlockFocus()
        return image
    }
}

/// Frame-rate-independent exponential ease toward `target`, taking the
/// shortest angular path (wraps at ±π). `tau` is the time to close ~63% of
/// the remaining gap; used for both facing and gaze easing.
private func easedAngle(current: Double, target: Double, tau: TimeInterval, deltaTime: TimeInterval) -> Double {
    let delta = normalizedAngle(target - current)
    let t = 1 - exp(-deltaTime / tau)
    return current + delta * t
}

/// Wraps an angle into `(-π, π]`.
private func normalizedAngle(_ angle: Double) -> Double {
    var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
    if a > .pi { a -= 2 * .pi }
    if a < -.pi { a += 2 * .pi }
    return a
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
