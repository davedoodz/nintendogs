import Foundation
import SceneKit

public struct AppliedAnimationClip {
    public let duration: TimeInterval
    public let targetNames: [String]
}

public enum AnimationLoader {
    public enum Error: Swift.Error, LocalizedError {
        case noMatchingChannels(URL)

        public var errorDescription: String? {
            switch self {
            case .noMatchingChannels(let url):
                "No animation channels in \(url.lastPathComponent) matched the pet rig."
            }
        }
    }

    /// Copies animation players from an exported rig onto matching nodes in the loaded pet rig.
    @discardableResult
    public static func apply(
        _ url: URL,
        to root: SCNNode,
        key: String,
        repeats: Bool
    ) throws -> AppliedAnimationClip {
        let clipScene = try SCNScene(url: url, options: ModelLoader.colladaOptions)
        var duration: TimeInterval = 0
        var targetNames: [String] = []

        clipScene.rootNode.enumerateHierarchy { sourceNode, _ in
            guard
                let name = sourceNode.name,
                let targetNode = root.childNode(withName: name, recursively: true)
            else { return }

            for sourceKey in sourceNode.animationKeys {
                guard let sourcePlayer = sourceNode.animationPlayer(forKey: sourceKey) else { continue }
                let animation = sourcePlayer.animation
                animation.repeatCount = repeats ? .infinity : 1
                let player = SCNAnimationPlayer(animation: animation)
                targetNode.addAnimationPlayer(player, forKey: "\(key).\(sourceKey)")
                player.play()
                duration = max(duration, animation.duration)
                if !targetNames.contains(name) { targetNames.append(name) }
            }
        }

        guard !targetNames.isEmpty else { throw Error.noMatchingChannels(url) }
        return AppliedAnimationClip(duration: duration, targetNames: targetNames)
    }
}
