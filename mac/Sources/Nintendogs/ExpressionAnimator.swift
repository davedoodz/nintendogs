import AppKit
import PetKit
import SceneKit

/// SceneKit evaluates transform constraints on its render queue. This lock-protected
/// value is the intentionally tiny bridge from main-actor updates to those callbacks.
final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func store(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func load() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private struct LifeFrame: Sendable {
    var tailPitch: CGFloat = 0
    var tailYaw: CGFloat = 0
    var tailTipPitch: CGFloat = 0
    var tailTipYaw: CGFloat = 0
    var chestPitch: CGFloat = 0
    var spinePitch: CGFloat = 0
    var waistRoll: CGFloat = 0
    var leftEarPitch: CGFloat = 0
    var rightEarPitch: CGFloat = 0
    var mouthPitch: CGFloat = 0
}

/// Owns the procedural expression layers that compose on top of authored clips.
@MainActor
final class ExpressionAnimator {
    private let snapshot = Locked(LifeFrame())
    private weak var tailNode: SCNNode?
    private weak var tailTipNode: SCNNode?
    private weak var chestNode: SCNNode?
    private weak var spineNode: SCNNode?
    private weak var waistNode: SCNNode?
    private weak var leftEarNode: SCNNode?
    private weak var rightEarNode: SCNNode?
    private weak var mouthNode: SCNNode?
    private var eyeMaterials: [SCNMaterial] = []
    private var eyeTextures: [PetEyeState: NSImage] = [:]
    private let tongueNode = SCNNode()
    private var frame = LifeFrame()
    private var tailPhase: Double = 0
    private var breathingPhase: Double = 0
    private var pantPhase: Double = 0
    private var blinkCountdown = Double.random(in: 3...7)
    private var blinkRemaining: TimeInterval = 0
    private var earFlickCountdown = Double.random(in: 4...12)
    private var earFlickRemaining: TimeInterval = 0
    private var flickLeftEar = true
    private var weightShiftCountdown = Double.random(in: 8...20)
    private var weightShiftTarget: CGFloat = 0
    private var currentEyeState: PetEyeState = .open
    private(set) var needsHighRate = false

    func configure(
        root: SCNNode,
        eyeMaterials: [SCNMaterial],
        eyeTextures: [PetEyeState: NSImage],
        tongueTexture: NSImage?
    ) {
        tailNode = root.childNode(withName: "tail2", recursively: true)
        tailTipNode = root.childNode(withName: "tail3", recursively: true)
        chestNode = root.childNode(withName: "chest", recursively: true)
        spineNode = root.childNode(withName: "spin", recursively: true)
        waistNode = root.childNode(withName: "waist", recursively: true)
        leftEarNode = root.childNode(withName: "Lear1", recursively: true)
        rightEarNode = root.childNode(withName: "Rear1", recursively: true)
        mouthNode = root.childNode(withName: "mouth", recursively: true)
        self.eyeMaterials = eyeMaterials
        self.eyeTextures = eyeTextures
        configureTongue(texture: tongueTexture)
        attachConstraints()
        applyEyeState(.open, force: true)
    }

    @discardableResult
    func update(
        deltaTime: TimeInterval,
        targets: PetExpressionTargets,
        tailSuppressed: Bool,
        mouthSuppressed: Bool
    ) -> Bool {
        guard deltaTime > 0 else { return needsHighRate }
        let dt = min(deltaTime, 0.1)
        tailPhase = (tailPhase + dt * targets.wagFrequencyHz).truncatingRemainder(dividingBy: 1)
        breathingPhase = (breathingPhase + dt * targets.breathingHz).truncatingRemainder(dividingBy: 1)
        pantPhase = (pantPhase + dt * 3.5).truncatingRemainder(dividingBy: 1)

        let radians = CGFloat.pi / 180
        let wagWeight: Double = tailSuppressed ? 0 : 1
        let tailYaw = wagWeight * (
            targets.wagBiasDegrees
                + targets.wagAmplitudeDegrees * sin(2 * .pi * tailPhase)
        )
        let tailTipYaw = wagWeight * (
            targets.wagBiasDegrees * 0.5
                + targets.wagAmplitudeDegrees * 0.55 * sin(2 * .pi * tailPhase - 0.9)
        )
        let breath = targets.breathingDegrees * sin(2 * .pi * breathingPhase)
        let pantSin = sin(2 * .pi * pantPhase)
        let pantAmount: Double
        if targets.mood == .content && targets.mouthOpenDegrees >= 10 {
            pantAmount = 1.5 * pantSin
        } else if targets.tongueOut > 0 {
            pantAmount = 2 + 2 * pantSin
        } else {
            pantAmount = 0
        }

        blinkRemaining = max(0, blinkRemaining - dt)
        if targets.eyes == .open {
            blinkCountdown -= dt
            if blinkCountdown <= 0 {
                blinkRemaining = 0.1
                blinkCountdown = Double.random(in: 3...7)
            }
        }
        let eyes = targets.eyes == .open && blinkRemaining > 0 ? PetEyeState.closed : targets.eyes
        applyEyeState(eyes)

        earFlickCountdown -= dt
        if earFlickCountdown <= 0 {
            earFlickRemaining = 0.2
            earFlickCountdown = Double.random(in: 4...12)
            flickLeftEar.toggle()
        }
        earFlickRemaining = max(0, earFlickRemaining - dt)
        let flickProgress = earFlickRemaining > 0 ? 1 - earFlickRemaining / 0.2 : 0
        let earFlick = earFlickRemaining > 0 ? -10 * sin(.pi * flickProgress) : 0

        weightShiftCountdown -= dt
        if weightShiftCountdown <= 0 {
            weightShiftTarget = Bool.random() ? 1.5 * radians : -1.5 * radians
            weightShiftCountdown = Double.random(in: 8...20)
        } else if weightShiftCountdown < 3 {
            weightShiftTarget *= CGFloat(exp(-dt / 0.8))
        }

        func smooth(_ current: CGFloat, _ target: CGFloat, tau: Double = 0.25) -> CGFloat {
            current + (target - current) * CGFloat(1 - exp(-dt / tau))
        }
        frame.tailPitch = smooth(
            frame.tailPitch,
            tailSuppressed ? 0 : CGFloat(targets.tailPitchDegrees) * radians,
            tau: 0.8
        )
        frame.tailYaw = smooth(frame.tailYaw, CGFloat(tailYaw) * radians)
        frame.tailTipPitch = smooth(
            frame.tailTipPitch,
            tailSuppressed ? 0 : CGFloat(targets.tailTipPitchDegrees) * radians,
            tau: 0.8
        )
        frame.tailTipYaw = smooth(frame.tailTipYaw, CGFloat(tailTipYaw) * radians)
        frame.chestPitch = smooth(frame.chestPitch, CGFloat(breath) * radians)
        frame.spinePitch = smooth(frame.spinePitch, CGFloat(breath * 0.4) * radians)
        frame.waistRoll = smooth(frame.waistRoll, weightShiftTarget, tau: 1)
        let baseEar = CGFloat(targets.earsBackDegrees) * radians
        frame.leftEarPitch = smooth(
            frame.leftEarPitch,
            baseEar + (flickLeftEar ? CGFloat(earFlick) * radians : 0)
        )
        frame.rightEarPitch = smooth(
            frame.rightEarPitch,
            baseEar + (!flickLeftEar ? CGFloat(earFlick) * radians : 0)
        )
        let mouthTarget = mouthSuppressed ? 0 : CGFloat(targets.mouthOpenDegrees + pantAmount) * radians
        frame.mouthPitch = smooth(frame.mouthPitch, mouthTarget)
        snapshot.store(frame)

        let tongueOut = mouthSuppressed ? 0 : CGFloat(targets.tongueOut) * (1 + 0.1 * CGFloat(pantSin))
        let tongueHidden = tongueOut < 0.01
        if tongueNode.isHidden != tongueHidden {
            tongueNode.isHidden = tongueHidden
        }
        let tongueZ = 0.12 + 0.25 * tongueOut
        if tongueNode.position.z != tongueZ {
            tongueNode.position.z = tongueZ
        }
        needsHighRate = targets.wagFrequencyHz >= 2 || (!mouthSuppressed && targets.tongueOut > 0)
        return needsHighRate
    }

    private func configureTongue(texture: NSImage?) {
        tongueNode.removeFromParentNode()
        guard let mouthNode, let texture else { return }
        let plane = SCNPlane(width: 0.26, height: 0.15)
        let material = SCNMaterial()
        material.diffuse.contents = texture
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.transparencyMode = .rgbZero
        material.diffuse.magnificationFilter = .nearest
        plane.materials = [material]
        tongueNode.name = "expression_tongue"
        tongueNode.geometry = plane
        tongueNode.eulerAngles = SCNVector3(-CGFloat.pi / 2 - 0.17, 0, 0)
        tongueNode.position = SCNVector3(0, -0.04, 0.12)
        tongueNode.isHidden = true
        mouthNode.addChildNode(tongueNode)
    }

    private func attachConstraints() {
        attachConstraint(to: tailNode) { ($0.tailPitch, $0.tailYaw, 0) }
        attachConstraint(to: tailTipNode) { ($0.tailTipPitch, $0.tailTipYaw, 0) }
        attachConstraint(to: chestNode) { ($0.chestPitch, 0, 0) }
        attachConstraint(to: spineNode) { ($0.spinePitch, 0, 0) }
        attachConstraint(to: waistNode) { (0, 0, $0.waistRoll) }
        attachConstraint(to: leftEarNode) { ($0.leftEarPitch, 0, 0) }
        attachConstraint(to: rightEarNode) { ($0.rightEarPitch, 0, 0) }
        attachConstraint(to: mouthNode) { ($0.mouthPitch, 0, 0) }
    }

    private func attachConstraint(
        to node: SCNNode?,
        angles: @escaping @Sendable (LifeFrame) -> (pitch: CGFloat, yaw: CGFloat, roll: CGFloat)
    ) {
        guard let node else { return }
        let snapshot = snapshot
        let transformBlock: @Sendable (SCNNode, SCNMatrix4) -> SCNMatrix4 = { _, transform in
            let value = angles(snapshot.load())
            let pitch = SCNMatrix4MakeRotation(value.pitch, 1, 0, 0)
            let yaw = SCNMatrix4MakeRotation(value.yaw, 0, 1, 0)
            let roll = SCNMatrix4MakeRotation(value.roll, 0, 0, 1)
            var result = SCNMatrix4Mult(transform, SCNMatrix4Mult(yaw, SCNMatrix4Mult(pitch, roll)))
            result.m41 = transform.m41
            result.m42 = transform.m42
            result.m43 = transform.m43
            return result
        }
        let constraint = SCNTransformConstraint(inWorldSpace: false, with: transformBlock)
        constraint.isIncremental = false
        node.constraints = (node.constraints ?? []) + [constraint]
    }

    private func applyEyeState(_ state: PetEyeState, force: Bool = false) {
        guard force || state != currentEyeState else { return }
        guard let texture = eyeTextures[state] else { return }
        currentEyeState = state
        for material in eyeMaterials {
            material.diffuse.contents = texture
        }
    }
}
