# Platform assessment: Swift native app vs web app

Question: which is easier to build for a one-week design sprint whose goal is a playable 3D puppy prototype with the DS-era Nintendogs look (soft lighting, low-poly puppy, touch petting, soap-bubble wash effect)?

## Decision

**Web app first (Three.js + React, served as a PWA on the phone).** Swift/RealityKit is the better long-term shipping target, but it loses the sprint on iteration speed, asset pipeline, and verification tooling. Re-assess after the sprint; port to Swift only if the prototype proves the idea and App Store distribution matters.

## Scorecard

| Criterion | Swift (SwiftUI + RealityKit/SceneKit) | Web (Three.js/R3F + Vite) | Winner |
|---|---|---|---|
| Time to first 3D puppy on screen | Half a day: Xcode project, RealityKit scene, USDZ import, simulator run | One hour: `npm create vite`, `@react-three/fiber`, load GLB, open in browser | Web |
| Hot reload / iteration loop | Xcode previews are flaky for RealityKit; full rebuild ~20-60s | Vite HMR under 1s; tweak shaders and lighting live | Web |
| 3D asset pipeline | Needs USDZ; GLB to USDZ conversion via Reality Converter adds a step; skeletal animation support in RealityKit is newer and less documented | GLB/glTF is native; Blender exports directly; thousands of tutorials for rigged animation | Web |
| Achieving the DS-era look (flat-ish lighting, soft shadows, low-poly) | Possible; RealityKit's PBR pipeline fights the look, needs custom materials/shaders (Metal) | Trivial with `MeshToonMaterial`, custom GLSL, post-processing passes | Web |
| Particle effects (soap bubbles, water) | RealityKit particle emitters exist (iOS 17+); SceneKit has `SCNParticleSystem`; both fine | `three-nebula` or instanced sprites; more manual but flexible | Tie |
| Touch input (petting, rubbing, drag brush) | UIKit gesture recognizers are excellent; pressure/haptics available | Pointer events fine; no haptics, no pressure | Swift |
| Haptics and "feel" | Core Haptics: real payoff for a petting game | Vibration API only, iOS Safari ignores it | Swift |
| Audio (bark, squeak, whistle) | AVFoundation; low latency | Web Audio; fine, but iOS Safari needs a user gesture to unlock | Swift |
| Microphone (naming the dog by voice, like the original) | Speech framework, on-device | Web Speech API, not supported in iOS Safari | Swift |
| Headless verification during the sprint | Requires simulator; screenshot via `xcrun simctl`; slower loop | Playwright/headless Chromium screenshots in seconds; matches this workstation's no-visible-window rule | Web |
| Cross-device sharing for feedback | TestFlight (needs signing, review delay for external) | Send a URL; works on any phone | Web |
| Performance ceiling on iPhone | Metal, full GPU, no browser tax | WebGL in Safari is good but throttled; WebGPU still partial on iOS | Swift |
| Distribution and monetization | App Store, IAP, but Apple review risk for a Nintendo-lookalike | Any host; no review; also no store discovery | Web (for sprint), Swift (for launch) |
| Persisting the dog (state, name, happiness) | SwiftData, trivial | localStorage / IndexedDB, trivial | Tie |
| Team skill fit (David: design + web + Swift) | Strong, but Swift 3D is the least-practiced corner | Strong; R3F is closest to existing web work | Web |
| Risk of tooling rabbit holes in a 5-day window | High: signing, RealityKit animation quirks, USDZ conversion | Low: mature docs, huge community | Web |

Tally: Web 9, Swift 4, Tie 3.

## Pros and cons, plainly

### Swift native (SwiftUI + RealityKit)

Pros
- Best possible feel: haptics, low-latency audio, on-device speech, gestures.
- Full GPU via Metal, no browser sandbox.
- App Store distribution and IAP if this becomes a product.
- Aligns with David's macOS/iOS skill set and existing Swift skills.

Cons
- Slowest iteration loop; RealityKit previews are unreliable.
- USDZ-only asset path; rigged animation is fiddly.
- DS-era stylized look fights RealityKit's PBR defaults; custom Metal shaders required.
- Sprint feedback needs TestFlight; external testers add review delay.
- Nintendo-lookalike risk at App Store review.

### Web app (React + Three.js / React Three Fiber)

Pros
- Fastest path to a playable 3D puppy; sub-second HMR.
- glTF/GLB native, Blender-friendly pipeline.
- Toon/flat shading is a one-liner; DS look is easy.
- Share a URL for instant feedback on any phone.
- Headless screenshot verification fits the workstation rules.

Cons
- No haptics, no pressure, no mic in iOS Safari; petting feels flatter.
- Audio needs a tap to unlock on iOS.
- WebGL performance ceiling lower than Metal; watch particle counts.
- No App Store presence; PWA install is a manual step users skip.

## What the sprint must prove before a Swift port is worth it

1. The puppy reads as "Nintendogs" at a glance (art direction, not tech).
2. Petting and washing are satisfying with touch alone, before haptics.
3. Someone besides David plays it for more than two minutes unprompted.

If all three hold, port the scene to RealityKit and keep the web build as the marketing demo.
