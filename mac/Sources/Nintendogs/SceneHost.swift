import SceneKit
import AppKit
import PetKit

/// Transparent SceneKit view with the DS-style fixed camera (KTD4), warm light and a blob shadow.
final class SceneHost: SCNView {
    static let dogHeight: CGFloat = 1.0
    /// Camera values ported from the web study (`src/scene.js`), rescaled for a 1-unit dog.
    private static let cameraPosition = SCNVector3(0, 0.78, 2.3)
    private static let cameraLook = SCNVector3(0, 0.48, 0)

    private let petAnchor = SCNNode()
    private let blobShadow = SCNNode()
    private var petClickPoint: CGPoint?
    var onCall: (() -> Void)?
    var onStroke: (() -> Void)?
    private var stroked = false
    private var lastStrokeTime: TimeInterval = 0
    private let bowl = SCNNode()
    private let bowlContents = SCNNode()
    private var displayedActivity: PetActivity?

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

    func setPet(_ node: SCNNode) {
        petAnchor.childNodes.forEach { $0.removeFromParentNode() }
        petAnchor.addChildNode(node)
        setNeedsDisplay(bounds)
    }

    func setAnimationActive(_ active: Bool) {
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
            petAnchor.removeAction(forKey: "approach")
            let destination = SCNVector3(0, 0, activity == .call ? 0.3 : 0)
            petAnchor.runAction(.move(to: destination, duration: 0.8), forKey: "approach")
        }
        bowl.isHidden = !caring
        if caring {
            bowlContents.geometry?.firstMaterial?.diffuse.contents =
                activity == .drink ? NSColor.systemBlue : NSColor.brown
            let deficit = activity == .drink ? needs.thirst : needs.hunger
            bowlContents.scale = SCNVector3(1, max(0.05, deficit / 100), 1)
            petAnchor.eulerAngles.y = .pi
        } else if activity == .call {
            petAnchor.eulerAngles.y = .pi
        }
    }

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
        onCall?()
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
