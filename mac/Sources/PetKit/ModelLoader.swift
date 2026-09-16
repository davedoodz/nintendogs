import SceneKit
import AppKit
public struct LoadedModel {
    public let node: SCNNode          // wrapper: feet at y=0, normalized height, centered on x/z
    public let rawHeight: CGFloat     // source units before scaling
    public let skinnedMeshCount: Int
}

public enum ModelLoader {
    /// Loads a Collada rip, wraps it, and scales it so its bounding height equals `targetHeight`.
    public static func load(_ url: URL, targetHeight: CGFloat) throws -> LoadedModel {
        let source = try SCNScene(url: url, options: [
            .checkConsistency: false,
            .convertToYUp: true,
            .flattenScene: false,
        ])
        let content = SCNNode()
        for child in source.rootNode.childNodes { content.addChildNode(child) }
        var skinned = 0

        let directory = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let textures = (
            eye: NSImage(contentsOf: directory.appendingPathComponent("eye_0.png")),
            body: NSImage(contentsOf: directory.appendingPathComponent("\(stem)_all.png")),
            paw: NSImage(contentsOf: directory.appendingPathComponent("\(stem)_hand.png"))
        )
        content.enumerateHierarchy { node, _ in
            if node.skinner != nil { skinned += 1 }
            for material in node.geometry?.materials ?? [] {
                material.lightingModel = .lambert
                material.specular.contents = NSColor.black
                material.multiply.contents = NSColor.white
                material.isDoubleSided = true
                let name = material.name?.lowercased() ?? ""
                let texture: NSImage? = name.contains("eye")
                    ? textures.eye
                    : name.contains("hand") ? textures.paw : textures.body
                material.diffuse.contents = texture
                material.diffuse.magnificationFilter = .nearest
                material.diffuse.minificationFilter = .linear
            }
        }

        let (minB, maxB) = content.boundingBox
        let height = max(maxB.y - minB.y, 0.0001)
        let scale = targetHeight / height
        content.scale = SCNVector3(scale, scale, scale)
        content.position = SCNVector3(
            -(minB.x + maxB.x) / 2 * scale,
            -minB.y * scale,
            -(minB.z + maxB.z) / 2 * scale
        )
        let wrapper = SCNNode()
        wrapper.name = "pet"
        wrapper.addChildNode(content)
        return LoadedModel(node: wrapper, rawHeight: height, skinnedMeshCount: skinned)
    }
}
