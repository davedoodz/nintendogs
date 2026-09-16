import SceneKit
import AppKit

/// Transparent SceneKit view with the DS-style fixed camera (KTD4), warm light and a blob shadow.
final class SceneHost: SCNView {
    static let dogHeight: CGFloat = 1.0
    /// Camera values ported from the web study (`src/scene.js`), rescaled for a 1-unit dog.
    private static let cameraPosition = SCNVector3(0, 0.78, 2.3)
    private static let cameraLook = SCNVector3(0, 0.48, 0)

    private let petAnchor = SCNNode()
    private let blobShadow = SCNNode()
    private var petClickPoint: CGPoint?

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
        isPlaying = false            // render on demand until animation exists (idle CPU budget)
        rendersContinuously = false

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
    }

    func setPet(_ node: SCNNode) {
        petAnchor.childNodes.forEach { $0.removeFromParentNode() }
        petAnchor.addChildNode(node)
        setNeedsDisplay(bounds)
    }

    /// Spin the pet a quarter turn; used from the menu while the rip's facing is being confirmed.
    func rotatePet() {
        petAnchor.eulerAngles.y += .pi / 2
        setNeedsDisplay(bounds)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let hit = hitTest(point, options: [SCNHitTestOption.firstFoundOnly: true])
        if let node = hit.first?.node, isPetNode(node) {
            petClickPoint = point
            return
        }
        petClickPoint = nil
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { petClickPoint = nil }
        guard let start = petClickPoint else {
            super.mouseUp(with: event)
            return
        }
        let end = convert(event.locationInWindow, from: nil)
        let distance = hypot(end.x - start.x, end.y - start.y)
        guard distance < 8 else { return }
        rotatePet()
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
