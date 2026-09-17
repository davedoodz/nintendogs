import AppKit
import PetKit
import SceneKit
import Testing
@testable import Nintendogs

/// `SCNVector3` components round-trip through Float32 storage, so a `0.1`
/// `CGFloat` literal can read back as `0.10000000149011612`; every comparison
/// against the wander band's edges tolerates that noise.
private let depthEpsilon: CGFloat = 1e-4

/// Regression coverage for the crop bug: `startCallApproach()` once hardcoded
/// its destination to `z: 0.3`, closer to the camera than `wanderZRange`'s
/// documented, measured-safe upper bound (`0.1`, "front paws clear the
/// panel's bottom edge"). That extra 0.2 units pulled the dog's ears past
/// the panel's top edge and its paws past the bottom during the whistle
/// call's `paws_up` finish.
@Test @MainActor func callApproachTargetsWithinTheDocumentedWanderDepthBand() throws {
    let host = SceneHost(frame: NSRect(x: 0, y: 0, width: 360, height: 240))
    let loaded = try ModelLoader.load(AssetLocator.shibaModel()!, targetHeight: SceneHost.dogHeight)
    try host.setPet(loaded.node, rawHeight: SceneHost.dogHeight)

    host.startCallApproach()

    let target = try #require(host.pendingWanderTargetForTesting)
    // The wander band's upper bound (0.1) is itself the measured "paws clear
    // the bottom edge" limit for a standing pose; paws_up is taller, so the
    // call approach must land strictly behind that edge, never past it.
    #expect(target.z <= 0.1 + depthEpsilon)
    #expect(target.z > -2.2)
}

/// Companion regression: autonomous eating/drinking used to walk the dog
/// straight onto the food bowl's raw prop position (`z: 0.55`), even further
/// past the camera than the call-approach bug above. The bowl itself now
/// sits at the wander band's edge, so any future prop move that pushes it
/// closer to the camera fails this test instead of silently re-cropping the
/// dog the next time it eats.
@Test @MainActor func bowlApproachTargetsWithinTheDocumentedWanderDepthBand() throws {
    let host = SceneHost(frame: NSRect(x: 0, y: 0, width: 360, height: 240))
    let loaded = try ModelLoader.load(AssetLocator.shibaModel()!, targetHeight: SceneHost.dogHeight)
    try host.setPet(loaded.node, rawHeight: SceneHost.dogHeight)

    host.startWander(running: false, towardBowl: true)

    let target = try #require(host.pendingWanderTargetForTesting)
    #expect(target.z <= 0.1 + depthEpsilon)
    #expect(target.z > -2.2)
}

/// Systemic backstop, not just the two known call sites above: any code
/// path (present or a future one nobody has audited yet) that ever sets the
/// pet anchor's depth outside `wanderZRange` gets pulled back inside it
/// within a single frame of `updatePresence`, the same way the existing X
/// backstop already corrects a resize that left the root outside the
/// walkable width.
@Test @MainActor func perFrameBackstopPullsAnOutOfBandDepthBackInRange() throws {
    let host = SceneHost(frame: NSRect(x: 0, y: 0, width: 360, height: 240))
    let loaded = try ModelLoader.load(AssetLocator.shibaModel()!, targetHeight: SceneHost.dogHeight)
    try host.setPet(loaded.node, rawHeight: SceneHost.dogHeight)

    // Simulate a future bug: something sets a depth outside the band
    // directly, bypassing beginTravel/randomWanderTarget entirely.
    host.setPetPose(position: SIMD2(0, 0.9), heading: 0)

    host.updatePresence(deltaTime: 1.0 / 60, activity: .idle, wandering: false)

    let z = host.debugPetAnchorPositionForTesting.z
    #expect(z <= 0.1 + depthEpsilon)
    #expect(z > -2.2)
}
