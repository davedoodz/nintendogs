import Foundation
import SceneKit

/// One imported animation channel: the rig node it targets (by name) and the
/// sampled motion for that node, straight out of the exported Collada file.
struct AnimationChannel {
    let nodeName: String
    let animation: SCNAnimation
}

/// A fully parsed clip file, not yet attached to any rig. Parsing never
/// mutates a scene graph, so a caller can validate every channel against a
/// target rig before deciding whether to attach anything.
struct LoadedClip {
    let name: String
    let duration: TimeInterval
    let channels: [AnimationChannel]
}

/// Internal to `PetKit`: only `AnimationController` parses clips. Nothing
/// outside the package touches `AnimationLoader` directly anymore.
enum AnimationLoader {
    enum Error: Swift.Error, LocalizedError {
        case noMatchingChannels(URL)

        var errorDescription: String? {
            switch self {
            case .noMatchingChannels(let url):
                "No animation channels in \(url.lastPathComponent) matched the pet rig."
            }
        }
    }

    /// Parses a Collada clip into raw per-node channels. Read-only: it never
    /// touches a pet rig, so callers can validate before mutating anything.
    static func load(_ url: URL, name: String) throws -> LoadedClip {
        let clipScene = try SCNScene(url: url, options: ModelLoader.colladaOptions)
        var duration: TimeInterval = 0
        var channels: [AnimationChannel] = []

        clipScene.rootNode.enumerateHierarchy { sourceNode, _ in
            guard let nodeName = sourceNode.name else { return }
            for key in sourceNode.animationKeys {
                guard let player = sourceNode.animationPlayer(forKey: key) else { continue }
                let animation = player.animation
                duration = max(duration, animation.duration)
                channels.append(AnimationChannel(nodeName: nodeName, animation: animation))
            }
        }

        guard !channels.isEmpty else { throw Error.noMatchingChannels(url) }
        return LoadedClip(name: name, duration: duration, channels: channels)
    }
}
