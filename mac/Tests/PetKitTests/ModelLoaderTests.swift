import Testing
import SceneKit
@testable import PetKit

@Test func shibaLoadsRiggedAndNormalized() throws {
    guard let url = AssetLocator.shibaModel() else {
        Issue.record("Shiba rip not present; run npm run assets:mac")
        return
    }
    let model = try ModelLoader.load(url, targetHeight: 1.0)
    #expect(model.skinnedMeshCount > 0, "rip should carry a skin controller")
    #expect(model.eyeMaterials.isEmpty == false, "rig should expose its eye material")
    #expect(model.eyeTextures.keys.sorted(by: { $0.rawValue < $1.rawValue })
        == PetEyeState.allCases.sorted(by: { $0.rawValue < $1.rawValue }))
    #expect(model.tongueTexture != nil)
    #expect(model.node.childNode(withName: "head", recursively: true) != nil,
            "head petting requires the authored head joint")
    let (minB, maxB) = model.node.boundingBox
    #expect(abs(Double(maxB.y - minB.y) - 1.0) < 0.01)
    #expect(abs(Double(minB.y)) < 0.01, "feet on the floor")
    #expect(abs(Double(minB.x + maxB.x)) < 0.02, "centred on x")
}
