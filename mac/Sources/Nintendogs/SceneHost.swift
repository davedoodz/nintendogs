import SceneKit
import AppKit
import PetKit

/// Fixed DS-style lens. File scope so the frustum maths below is not main-actor bound.
private enum CameraLens {
    static let fieldOfView: Double = 38
    static let zNear: Double = 0.05
    static let zFar: Double = 40
}



/// Transparent SceneKit view with the DS-style fixed camera (KTD4), warm light and a blob shadow.
final class SceneHost: SCNView {
    static let dogHeight: CGFloat = 1.0
    /// Camera values ported from the web study (`src/scene.js`), rescaled for a 1-unit dog.
    private static let cameraPosition = SCNVector3(0, 0.78, 2.3)
    private static let cameraLook = SCNVector3(0, 0.48, 0)

    /// Fetch arena clamps (KTD6). A throw lands no farther than `arenaZFar`; rays that pass
    /// above the horizon — most of the display, since the camera looks only ~7 degrees down —
    /// are pulled onto that depth, so higher on screen reads as farther away. `arenaXLimit`
    /// keeps the ball on the display at that depth.
    static let arenaZFar: Double = -8
    static let arenaZNear: Double = 0.6
    static let arenaXLimit: Double = 6

    /// Depth band wander targets are picked within. The near end is where the
    /// front paws still clear the panel's bottom edge (measured: z ≈ 0 with the
    /// fixed lens); the far end shrinks the dog to about half size, so a leg
    /// toward or away from the camera reads as real depth, not lateral drift.
    private static let wanderZRange: ClosedRange<CGFloat> = -2.2...0.1
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
    var onBallPicked: (() -> Void)?
    private var stroked = false
    private var lastStrokeTime: TimeInterval = 0
    private let bowl = SCNNode()
    private let bowlContents = SCNNode()
    private var displayedActivity: PetActivity?
    private let ballRoot = SCNNode()
    private let ballShadow = SCNNode()
    private weak var mouthNode: SCNNode?
    private(set) var ballAttached = false
    private var ballFlight: BallFlight?
    private var lastBounceCount = 0
    /// How long an impact squash lasts. Longer than one loop tick, so the deformation is on
    /// screen for at least one rendered frame.
    private static let ballSquashDuration: TimeInterval = 0.18
    /// Seconds left of the post-impact squash; drives `ballRoot.scale` only while positive.
    private var ballSquash: TimeInterval = 0
    /// Ground ring showing where a held ball would land, and the spot the dog aims at while
    /// the ball is on the cursor (R2, R4).
    private let aimMarker = SCNNode()
    private var aimTarget: SIMD2<Double>?
    /// The home frame recorded by `applyHomeProjection(home:arena:)`, so the region visible
    /// in the home panel stays computable while the view covers the whole screen (KTD5).
    private var arenaHomeFrame: NSRect?
    var hasBall: Bool { ballRoot.parent != nil }
    var ballGroundPosition: SIMD2<Double>? {
        guard hasBall else { return nil }
        let world = ballRoot.worldPosition
        return SIMD2(Double(world.x), Double(world.z))
    }

    /// Held as a property so the arena can retarget the projection and turn screen points
    /// into ground points (KTD4, KTD6).
    private let cameraNode = SCNNode()
    /// The frustum forced onto the camera while the panel is expanded to the arena.
    /// `nil` means the ordinary home projection is in effect.
    private var arenaFrustum: Frustum?

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
    private var isCallApproaching = false

    // MARK: Gaze

    private weak var headNode: SCNNode?
    private var gazeYaw: CGFloat = 0
    private var gazePitch: CGFloat = 0
    private let gazeSnapshot = Locked(SCNVector3(0, 0, 0))

    // MARK: Expression layers

    private let expressionAnimator = ExpressionAnimator()
    var expressionNeedsHighRate: Bool { expressionAnimator.needsHighRate }

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
        // The Retina backing scale already smooths edges; MSAA kept the release process above
        // the 120 MB resident-memory gate, especially after the arena render target expanded.
        antialiasingMode = .none
        preferredFramesPerSecond = 30
        setAnimationActive(false)    // render on demand until animation exists (idle CPU budget)

        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(CameraLens.fieldOfView)
        camera.zNear = CameraLens.zNear
        camera.zFar = CameraLens.zFar
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
        configureBall(in: scene)
    }

    func setPet(
        _ node: SCNNode,
        rawHeight: CGFloat,
        eyeMaterials: [SCNMaterial] = [],
        eyeTextures: [PetEyeState: NSImage] = [:],
        tongueTexture: NSImage? = nil
    ) throws {
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
        mouthNode = node.childNode(withName: "mouth", recursively: true)
        expressionAnimator.configure(
            root: node,
            eyeMaterials: eyeMaterials,
            eyeTextures: eyeTextures,
            tongueTexture: tongueTexture
        )
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
            if caring {
                // Care bowls return to the home position. Other interactions
                // preserve the pet's current root; call choreography owns its
                // explicit run toward the camera.
                stopWander()
                petAnchor.removeAction(forKey: "approach")
                petAnchor.runAction(.move(to: SCNVector3(0, 0, 0), duration: 0.8), forKey: "approach")
            }
        }
        bowl.isHidden = !caring
        if caring {
            bowlContents.geometry?.firstMaterial?.diffuse.contents =
                activity == .drink ? NSColor.systemBlue : NSColor.brown
            let deficit = activity == .drink ? needs.thirst : needs.hunger
            bowlContents.scale = SCNVector3(1, max(0.05, deficit / 100), 1)
            petAnchor.eulerAngles.y = 0
        }
    }

    // MARK: - Fetch object and root pose (KTD6, KTD7)

    private func configureBall(in scene: SCNScene) {
        let sphere = SCNSphere(radius: 0.08)
        sphere.segmentCount = 24
        let felt = SCNMaterial()
        felt.diffuse.contents = NSColor(calibratedRed: 0.72, green: 0.84, blue: 0.16, alpha: 1)
        felt.roughness.contents = 0.82
        sphere.firstMaterial = felt
        let body = SCNNode(geometry: sphere)
        body.name = "fetchBall"
        ballRoot.addChildNode(body)

        let seamRotations: [SCNVector3] = [
            SCNVector3(CGFloat.pi / 2, 0, 0),
            SCNVector3(0, 0, CGFloat.pi / 2),
        ]
        for rotation in seamRotations {
            let seam = SCNTorus(ringRadius: 0.063, pipeRadius: 0.005)
            seam.ringSegmentCount = 24
            seam.pipeSegmentCount = 8
            seam.firstMaterial?.diffuse.contents = NSColor.white.withAlphaComponent(0.9)
            let node = SCNNode(geometry: seam)
            node.eulerAngles = rotation
            node.name = "fetchBallSeam"
            ballRoot.addChildNode(node)
        }
        ballRoot.name = "fetchBallRoot"
        ballRoot.isHidden = true

        ballShadow.geometry = SCNPlane(width: 0.20, height: 0.14)
        let shadow = SCNMaterial()
        shadow.diffuse.contents = Self.blobShadowImage()
        shadow.lightingModel = .constant
        shadow.isDoubleSided = true
        shadow.writesToDepthBuffer = false
        ballShadow.geometry?.materials = [shadow]
        ballShadow.eulerAngles.x = -.pi / 2
        ballShadow.position.y = 0.003
        // Drawn before the ball: the plane does not write depth, so without an explicit
        // order it can paint over the resting ball's lower half and flatten its silhouette.
        ballShadow.renderingOrder = -1
        ballShadow.isHidden = true
        configureAimMarker()
        scene.rootNode.addChildNode(aimMarker)
        scene.rootNode.addChildNode(ballRoot)
        scene.rootNode.addChildNode(ballShadow)
    }

    /// A flat ring, unlit and depth-transparent so it reads as a mark on the ground rather
    /// than an object standing on it.
    private func configureAimMarker() {
        let ring = SCNTorus(ringRadius: 0.2, pipeRadius: 0.02)
        ring.ringSegmentCount = 32
        ring.pipeSegmentCount = 6
        let material = SCNMaterial()
        material.diffuse.contents = NSColor(calibratedRed: 0.72, green: 0.84, blue: 0.16, alpha: 0.9)
        material.lightingModel = .constant
        material.writesToDepthBuffer = false
        ring.firstMaterial = material
        aimMarker.geometry = ring
        aimMarker.position.y = 0.005
        aimMarker.opacity = 0.95
        aimMarker.isHidden = true
    }

    func setPetPose(position: SIMD2<Double>, heading: Double) {
        stopWander()
        petAnchor.removeAction(forKey: "approach")
        petAnchor.position = SCNVector3(position.x, 0, position.y)
        petAnchor.eulerAngles.y = CGFloat(heading)
        blobShadow.position = SCNVector3(position.x, blobShadow.position.y, position.y)
    }

    func placeBall(at position: SIMD2<Double>) {
        ballRoot.removeAllActions()
        ballFlight = nil
        if ballRoot.parent !== scene?.rootNode {
            ballRoot.removeFromParentNode()
            scene?.rootNode.addChildNode(ballRoot)
        }
        ballAttached = false
        ballRoot.scale = SCNVector3(1, 1, 1)
        ballRoot.position = SCNVector3(position.x, 0.08, position.y)
        ballRoot.isHidden = false
        ballShadow.position = SCNVector3(position.x, ballShadow.position.y, position.y)
        ballShadow.scale = SCNVector3(1, 1, 1)
        ballShadow.opacity = 1
        ballShadow.isHidden = false
        setNeedsDisplay(bounds)
    }

    /// Launches the ball so its first impact is `landing`, then lets it bounce and roll to
    /// rest (R6). Returns the spot it will come to rest on, which is what the dog chases from
    /// the moment of the throw (R8).
    @discardableResult
    func throwBall(to landing: SIMD2<Double>) -> SIMD2<Double> {
        attachBall(toMouth: false)
        let launch = SIMD3<Double>(
            Double(petAnchor.position.x),
            Double(petAnchor.position.y) + 0.9,
            Double(petAnchor.position.z) + 1.6
        )
        let flight = BallFlight(
            launch: launch,
            aim: landing,
            bounds: BallFlight.Bounds(
                xLimit: Self.arenaXLimit,
                zNear: Self.arenaZNear,
                zFar: Self.arenaZFar
            )
        )
        ballRoot.removeAllActions()
        if ballRoot.parent !== scene?.rootNode {
            ballRoot.removeFromParentNode()
            scene?.rootNode.addChildNode(ballRoot)
        }
        ballRoot.scale = SCNVector3(1, 1, 1)
        ballRoot.eulerAngles = SCNVector3(0, 0, 0)
        ballRoot.isHidden = false
        ballShadow.isHidden = false
        lastBounceCount = 0
        ballSquash = 0
        ballFlight = flight
        applyFlight(flight)
        return flight.predictedRest
    }

    /// Advances the in-flight ball. Returns its ground position and whether it has stopped;
    /// `nil` when no throw is in flight.
    @discardableResult
    func advanceBallFlight(by deltaTime: TimeInterval) -> (ground: SIMD2<Double>, atRest: Bool)? {
        guard var flight = ballFlight else { return nil }
        flight.advance(by: deltaTime)
        // Decay first, then arm: the loop's tick is longer than the squash, so arming last is
        // what guarantees the impact frame actually renders squashed.
        ballSquash = max(0, ballSquash - deltaTime)
        if flight.bounceCount != lastBounceCount {
            lastBounceCount = flight.bounceCount
            ballSquash = Self.ballSquashDuration
        }
        applyFlight(flight)
        let result = (flight.groundPosition, flight.isAtRest)
        ballFlight = flight.isAtRest ? nil : flight
        if flight.isAtRest {
            ballRoot.scale = SCNVector3(1, 1, 1)
            ballShadow.scale = SCNVector3(1, 1, 1)
            ballShadow.opacity = 1
        }
        return result
    }

    /// Renders one flight sample: position, spin, impact squash, and a shadow that shrinks
    /// and fades with height so altitude reads on the ground (R7).
    private func applyFlight(_ flight: BallFlight) {
        let ground = flight.groundPosition
        ballRoot.position = SCNVector3(ground.x, flight.height, ground.y)
        // Roll about the axis perpendicular to travel: a ball that visibly spins the way it
        // moves is most of what separates "thrown object" from "moving sprite".
        let speed = hypot(flight.velocity.x, flight.velocity.z)
        if speed > 1e-6 {
            let axis = SCNVector3(CGFloat(flight.velocity.z / speed), 0, CGFloat(-flight.velocity.x / speed))
            let angle = CGFloat(flight.travelled / BallFlight.radius)
            ballRoot.rotation = SCNVector4(axis.x, axis.y, axis.z, angle)
        }
        if ballSquash > 0 {
            // Squared falloff: the deformation is only at full strength on the contact frame
            // and is nearly gone a frame later, which reads as an impact rather than a
            // permanently flattened ball.
            let phase = ballSquash / Self.ballSquashDuration
            let amount = CGFloat(phase * phase) * 0.14
            ballRoot.scale = SCNVector3(1 + amount * 0.5, 1 - amount, 1 + amount * 0.5)
        } else {
            ballRoot.scale = SCNVector3(1, 1, 1)
        }
        let altitude = min(max((flight.height - BallFlight.radius) / 1.8, 0), 1)
        ballShadow.position = SCNVector3(ground.x, ballShadow.position.y, ground.y)
        ballShadow.opacity = 1 - 0.7 * CGFloat(altitude)
        let shrink = 1 - 0.35 * CGFloat(altitude)
        ballShadow.scale = SCNVector3(shrink, shrink, 1)
    }

    func attachBall(toMouth attach: Bool) {
        guard attach != ballAttached else { return }
        ballRoot.removeAllActions()
        if attach, let mouthNode {
            ballRoot.removeFromParentNode()
            mouthNode.addChildNode(ballRoot)
            ballRoot.position = SCNVector3(0, 0, 0)
            ballRoot.eulerAngles = SCNVector3(0, 0, 0)
            ballAttached = true
            updateAttachedBallTransform()
            ballShadow.isHidden = true
        } else {
            let world = ballRoot.presentation.worldPosition
            ballRoot.removeFromParentNode()
            scene?.rootNode.addChildNode(ballRoot)
            ballRoot.worldPosition = world
            ballAttached = false
            ballShadow.isHidden = ballRoot.isHidden
            ballShadow.position = SCNVector3(world.x, ballShadow.position.y, world.z)
        }
    }

    /// Cancels the imported skeleton's animated uniform scale while the ball follows `mouth`.
    func updateAttachedBallTransform() {
        guard ballAttached, let mouthNode else { return }
        let transform = mouthNode.presentation.simdWorldTransform
        let xAxis = SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
        let inheritedScale = max(simd_length(xAxis), Float.ulpOfOne)
        ballRoot.simdScale = SIMD3<Float>(repeating: 1 / inheritedScale)
    }

    func removeBall() {
        ballRoot.removeAllActions()
        ballFlight = nil
        ballRoot.removeFromParentNode()
        ballRoot.isHidden = true
        ballShadow.isHidden = true
        ballAttached = false
        setNeedsDisplay(bounds)
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
        if isWandering, wandering, wanderEnabled || isCallApproaching {
            stepWander(deltaTime: deltaTime)
        }
        let viewPoint = cursorViewPoint(override: cursorOverride)
        updateCursorState(viewPoint: viewPoint)
        updateGaze(deltaTime: deltaTime, activity: activity, viewPoint: viewPoint)
        blobShadow.position = SCNVector3(petAnchor.position.x, blobShadow.position.y, petAnchor.position.z)
    }

    /// Picks a wander target — the bowl, or a random point within the
    /// current walkable bounds — and commits to a gait for it. A requested
    /// run downgrades to a walk if the picked target turns out too close to
    /// justify running; check `isRunning` afterward to see which was actually
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
        beginTravel(to: target, running: running && distance >= runThreshold, callApproach: false)
    }

    /// Runs toward the near, centered call position even when autonomous
    /// wandering is disabled. The caller owns the run clip.
    func startCallApproach() {
        guard gaitSpeeds != nil else { return }
        beginTravel(
            to: SCNVector3(0, petAnchor.position.y, 0.3),
            running: true,
            callApproach: true
        )
    }

    private func beginTravel(to target: SCNVector3, running: Bool, callApproach: Bool) {
        petAnchor.removeAction(forKey: "approach")
        wanderTarget = target
        isWandering = true
        isRunning = running
        isCallApproaching = callApproach
    }

    /// Hard-cancels any in-progress or pending wander: clears the target and
    /// gait, and stops root translation immediately. Call on interactions,
    /// care, or any other suppression — safe to call at any time, including
    /// when not wandering.
    func stopWander() {
        wanderTarget = nil
        isWandering = false
        isRunning = false
        isCallApproaching = false
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
            isCallApproaching = false
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

    // MARK: - Fetch arena (KTD4, KTD6)

    /// An explicit view frustum, in near-plane units.
    ///
    /// The arena owns the whole projection instead of composing onto SceneKit's, because
    /// SceneKit will not cooperate with a partial override: `SCNCamera.projectionTransform`
    /// reports an aspect-free matrix on read, and `SCNView.projectPoint`/`unprojectPoint`
    /// ignore an override entirely. `symmetric(aspect:)` reproduces SceneKit's own projection
    /// pixel-for-pixel, and every screen/world conversion here goes through these parameters,
    /// so hit-testing always agrees with what renders.
    struct Frustum: Equatable {
        var left: Double
        var right: Double
        var bottom: Double
        var top: Double
        var near: Double
        var far: Double

        /// Row-vector convention, matching `SCNMatrix4`: translation in m41..m43, `w' = -z`.
        var matrix: SCNMatrix4 {
            var m = SCNMatrix4()
            m.m11 = CGFloat(2 * near / (right - left))
            m.m22 = CGFloat(2 * near / (top - bottom))
            m.m31 = CGFloat((right + left) / (right - left))
            m.m32 = CGFloat((top + bottom) / (top - bottom))
            m.m33 = CGFloat(-(far + near) / (far - near))
            m.m34 = -1
            m.m43 = CGFloat(-2 * far * near / (far - near))
            return m
        }

        /// The centred frustum SceneKit itself would use for `aspect`.
        static func symmetric(aspect: Double) -> Frustum {
            let top = CameraLens.zNear * tan(CameraLens.fieldOfView * .pi / 360)
            return Frustum(
                left: -top * aspect, right: top * aspect,
                bottom: -top, top: top,
                near: CameraLens.zNear, far: CameraLens.zFar
            )
        }

        /// The off-centre frustum that makes a viewport covering `arena` show the same world
        /// at the same screen pixels as one covering `home` did. Scale is preserved by keeping
        /// near-plane units per screen point constant; the home spot is preserved by shifting
        /// the frustum so the camera axis still lands on `home`'s centre.
        static func arena(home: NSRect, arena: NSRect) -> Frustum {
            let homeFrustum = symmetric(aspect: Double(home.width / home.height))
            let unitsPerPoint = Double(home.width) / (homeFrustum.right - homeFrustum.left)
            let width = Double(arena.width) / unitsPerPoint
            let height = Double(arena.height) / unitsPerPoint
            let tx = 2 * Double(home.midX - arena.midX) / Double(arena.width)
            let ty = 2 * Double(home.midY - arena.midY) / Double(arena.height)
            return Frustum(
                left: -width * (1 + tx) / 2, right: width * (1 - tx) / 2,
                bottom: -height * (1 + ty) / 2, top: height * (1 - ty) / 2,
                near: homeFrustum.near, far: homeFrustum.far
            )
        }
    }

    /// True while the panel is expanded to the arena.
    var isInArena: Bool { arenaFrustum != nil }

    /// Forces the projection that keeps `home`'s mapping while the view covers `arena`.
    /// Apply this before resizing the panel so no frame renders with the wrong projection.
    func applyHomeProjection(home: NSRect, arena: NSRect) {
        let frustum = Frustum.arena(home: home, arena: arena)
        arenaFrustum = frustum
        arenaHomeFrame = home
        cameraNode.camera?.projectionTransform = frustum.matrix
    }

    /// Returns to the ordinary home projection. Call after the panel is back at its home frame.
    func restoreProjection() {
        arenaFrustum = nil
        arenaHomeFrame = nil
        applyHomeProjection()
    }

    /// Re-derives the centred projection for the current view size. The panel locks a 3:2
    /// content aspect, so this is stable across resizes.
    private func applyHomeProjection() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        cameraNode.camera?.projectionTransform =
            Frustum.symmetric(aspect: Double(bounds.width / bounds.height)).matrix
    }

    override func layout() {
        super.layout()
        // The arena's frustum is absolute; only the home projection tracks the view size.
        if arenaFrustum == nil { applyHomeProjection() }
    }

    private var currentFrustum: Frustum? {
        if let arenaFrustum { return arenaFrustum }
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        return .symmetric(aspect: Double(bounds.width / bounds.height))
    }

    /// This view's rect in screen coordinates.
    private var screenViewport: NSRect? {
        guard let window, bounds.width > 0, bounds.height > 0 else { return nil }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    /// Turns a screen point into a spot on the dog's ground plane, as `(x, z)` (KTD6).
    ///
    /// Every on-screen point yields a spot: a ray that passes above the horizon keeps its
    /// heading and lands at the far clamp, which is what makes "higher on screen means
    /// farther away" hold all the way to the top of the display.
    func groundPoint(forScreenPoint screenPoint: NSPoint) -> SIMD2<Double>? {
        guard let viewport = screenViewport, let frustum = currentFrustum else { return nil }
        let ndcX = 2 * Double(screenPoint.x - viewport.minX) / Double(viewport.width) - 1
        let ndcY = 2 * Double(screenPoint.y - viewport.minY) / Double(viewport.height) - 1
        let xView = (ndcX * (frustum.right - frustum.left) + (frustum.right + frustum.left)) / 2
        let yView = (ndcY * (frustum.top - frustum.bottom) + (frustum.top + frustum.bottom)) / 2
        let transform = cameraNode.simdWorldTransform
        let heading = transform * SIMD4<Float>(Float(xView), Float(yView), Float(-frustum.near), 0)
        let direction = SIMD3<Double>(Double(heading.x), Double(heading.y), Double(heading.z))
        let origin = SIMD3<Double>(
            Double(transform.columns.3.x),
            Double(transform.columns.3.y),
            Double(transform.columns.3.z)
        )
        var landing: SIMD2<Double>?
        if direction.y < -1e-9 {
            let distance = -origin.y / direction.y
            if distance > 0 {
                landing = SIMD2(
                    origin.x + distance * direction.x,
                    origin.z + distance * direction.z
                )
            }
        }
        if landing == nil {
            if direction.z < -1e-9 {
                let distance = (Self.arenaZFar - origin.z) / direction.z
                landing = SIMD2(origin.x + distance * direction.x, Self.arenaZFar)
            } else {
                landing = SIMD2(origin.x, Self.arenaZFar)
            }
        }
        var ground = landing ?? SIMD2(origin.x, Self.arenaZFar)
        ground.y = min(max(ground.y, Self.arenaZFar), Self.arenaZNear)
        ground.x = min(max(ground.x, -Self.arenaXLimit), Self.arenaXLimit)
        return ground
    }

    // MARK: - Aim (R2, R4)

    /// The ground spot the held ball is aimed at: shows the marker there, and gives the dog
    /// something to turn toward and watch. Pass `nil` to clear.
    func setAimTarget(_ ground: SIMD2<Double>?) {
        aimTarget = ground
        guard let ground else {
            aimMarker.isHidden = true
            return
        }
        aimMarker.position = SCNVector3(ground.x, aimMarker.position.y, ground.y)
        aimMarker.isHidden = false
        setNeedsDisplay(bounds)
    }

    /// Eases the body yaw and head gaze toward the aim spot. Called every tick while an item
    /// is on the cursor, in place of `updatePresence` — the cursor is usually outside this
    /// view's bounds while aiming, which the presence path's "nearby" gate would reject.
    func advanceAim(deltaTime: TimeInterval) {
        guard deltaTime > 0, let aimTarget else { return }
        let dx = Double(aimTarget.x) - Double(petAnchor.position.x)
        let dz = Double(aimTarget.y) - Double(petAnchor.position.z)
        if hypot(dx, dz) > 0.05 {
            petAnchor.eulerAngles.y = CGFloat(easedAngle(
                current: Double(petAnchor.eulerAngles.y),
                target: atan2(dx, dz),
                tau: Self.facingEaseTau,
                deltaTime: deltaTime
            ))
        }
        // Eyes on the ball, which is at the cursor, not on the ground: aim a little above the
        // marked spot so the head lifts rather than dropping to the floor.
        let look = SCNVector3(aimTarget.x, 0.55, aimTarget.y)
        var target: (yaw: CGFloat, pitch: CGFloat) = (0, 0)
        if let head = headNode, let aim = gazeAim(atWorld: look, head: head) { target = aim }
        gazeYaw = CGFloat(easedAngle(
            current: Double(gazeYaw), target: Double(target.yaw), tau: Self.gazeEaseTau, deltaTime: deltaTime
        ))
        gazePitch = CGFloat(easedAngle(
            current: Double(gazePitch), target: Double(target.pitch), tau: Self.gazeEaseTau, deltaTime: deltaTime
        ))
        gazeSnapshot.store(SCNVector3(gazePitch, gazeYaw, petAnchor.eulerAngles.y))
        blobShadow.position = SCNVector3(petAnchor.position.x, blobShadow.position.y, petAnchor.position.z)
    }

    /// Pulls `point` into the ground region that is visible in the home panel, so a dog sent
    /// there - and the ball it presents once it arrives - are still on screen after the arena
    /// collapses (KTD5).
    ///
    /// Uses the recorded home frame and its own frustum maths rather than
    /// `walkableXRange`, whose `projectPoint`/`unprojectPoint` calls ignore the arena
    /// projection override and would answer for the full-screen viewport instead.
    func homeRegionClamp(_ point: SIMD2<Double>) -> SIMD2<Double> {
        let home = arenaHomeFrame ?? bounds
        guard home.width > 0, home.height > 0 else { return point }
        let frustum = Frustum.symmetric(aspect: Double(home.width / home.height))
        // Leave the drop's depth in hand: the dog sets the ball down that much nearer the
        // camera, and a dog standing on the near edge would present it past that edge.
        let nearest = Double(Self.wanderZRange.upperBound) - FetchSequence.dropDistance
        let z = min(max(point.y, Double(Self.wanderZRange.lowerBound)), nearest)
        // Size the lateral limit where the pair sits closest to the camera - the ball's spot -
        // because that is where the visible ground is narrowest.
        let visible = groundHalfWidth(atZ: z + FetchSequence.dropDistance, frustum: frustum)
        guard visible > 0 else { return SIMD2(0, z) }
        // Keep a couple of body radii off the visible edge so nothing is half-clipped once
        // the arena collapses - but never more than a third of the range, because close to
        // the camera the panel is only ~1 unit wide and a fixed margin would collapse every
        // target onto x = 0, which reads as "always returns to the middle" (R10).
        let margin = min(Double(petRadius) * 2.5, visible / 3)
        let halfWidth = visible - margin
        return SIMD2(min(max(point.x, -halfWidth), halfWidth), z)
    }

    /// Half the width of the ground plane visible at depth `z` under `frustum`. The camera
    /// has pitch only, so view-space x is world x and one depth read is enough.
    private func groundHalfWidth(atZ z: Double, frustum: Frustum) -> Double {
        let inverse = simd_inverse(cameraNode.simdWorldTransform)
        let view = inverse * SIMD4<Float>(0, 0, Float(z), 1)
        let depth = Double(-view.z)
        guard depth > frustum.near else { return 0 }
        return frustum.right * depth / frustum.near
    }

    // MARK: - Expression layers

    func updateExpression(
        deltaTime: TimeInterval,
        targets: PetExpressionTargets,
        tailSuppressed: Bool
    ) {
        expressionAnimator.update(
            deltaTime: deltaTime,
            targets: targets,
            tailSuppressed: tailSuppressed,
            mouthSuppressed: ballAttached
        )
        setNeedsDisplay(bounds)
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
        let snapshot = gazeSnapshot
        let transformBlock: @Sendable (SCNNode, SCNMatrix4) -> SCNMatrix4 = { _, transform in
            let angles = snapshot.load()
            let yaw = SCNMatrix4MakeRotation(angles.y, 0, 1, 0)
            let pitch = SCNMatrix4MakeRotation(-angles.x, cos(angles.z), 0, -sin(angles.z))
            var result = SCNMatrix4Mult(transform, SCNMatrix4Mult(yaw, pitch))
            // Rotate orientation about the head joint, never its position.
            result.m41 = transform.m41
            result.m42 = transform.m42
            result.m43 = transform.m43
            return result
        }
        let constraint = SCNTransformConstraint(inWorldSpace: true, with: transformBlock)
        // SceneKit defaults transform constraints to incremental evaluation, which feeds the
        // previous rendered result into the next frame and can compound a small gaze offset
        // into a full head rotation. Always compose from that frame's authored animation pose.
        constraint.isIncremental = false
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
        gazeSnapshot.store(SCNVector3(gazePitch, gazeYaw, petAnchor.eulerAngles.y))
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
        return gazeAim(atWorld: targetWorld, head: head)
    }

    /// The same aim, for a target already known in world space (the aim marker's spot).
    private func gazeAim(atWorld targetWorld: SCNVector3, head: SCNNode) -> (yaw: CGFloat, pitch: CGFloat)? {
        let headWorld = head.presentation.worldPosition
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
        if let node = hit.first?.node, isBallNode(node), !ballAttached {
            removeBall()
            onBallPicked?()
            return
        }
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

    private func isBallNode(_ node: SCNNode) -> Bool {
        var current: SCNNode? = node
        while let candidate = current {
            if candidate === ballRoot { return true }
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
