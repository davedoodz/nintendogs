---
title: Notch Item Tray and Desktop Fetch - Plan
type: feat
date: 2026-09-16
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-plan-bootstrap
execution: code
---

# Notch Item Tray and Desktop Fetch - Plan

## Goal Capsule

- **Objective:** David can hover the MacBook notch, pick one of the Shiba's objects as a 2D sprite, carry it on the cursor, and throw a ball anywhere on the screen; the dog runs to it, picks it up, and brings it back to him. The existing paw menu is not the entry point for this.
- **Means:** a notch-anchored hover tray (KTD1), a held-item overlay that owns the cursor (KTD3), and a screen-sized fetch arena that keeps the dog's current on-screen scale and home spot (KTD4), driven by a deterministic `FetchSequence` in PetKit (KTD5).
- **Authority:** this plan, then `docs/ANIMATION_CONTRACT.md` for clip semantics, then existing code conventions in `mac/Sources`.
- **Stop conditions:** stop and ask if (a) a window over the notch cannot receive `mouseEntered` on David's machine (KTD1 fallback also fails), or (b) `SCNCamera.projectionTransform` cannot hold the home mapping during arena expansion (KTD4 fallback is a visible change David must accept).
- **Execution profile:** single-machine Mac work in `mac/Sources` and `mac/Assets`. No new Blender clips; Windows session is not involved.
- **Finish and ship:** implementer builds the `.app`, verifies with window screenshots, commits on `feat/desktop-recreation`, and David accepts the visual direction.

## Product Contract

### Summary

Add a hover tray that drops out of the notch (Clicky-style) listing the dog's objects as 2D sprites. Clicking a sprite puts the item on the cursor. Clicking the desktop throws the item into the dog's world; a ball starts a fetch: the dog runs to the ball across the screen, picks it up, carries it back to its home spot, drops it, and celebrates. Bowls dropped anywhere start the existing feed/water interactions.

### Problem Frame

Today every interaction goes through the paw menu (`StatusMenu.swift`). Fetch does not exist, the 24 authored clips include `shiba_run_loop`, `shiba_fetch_pickup`, and `shiba_fetch_carry_loop` that nothing reaches autonomously, and the dog's root never moves (`docs/ALIVENESS_PLAN.md` lines 13-14). The pet panel is a 720×480 window, so a throw "anywhere on the screen" has nowhere to land. David wants a physical, direct-manipulation entry point that feels like the DS stylus, not a menu.

### Key Decisions

- **Notch tray is the only entry point for objects; the paw menu is unchanged.** (session-settled: user-directed — chosen over a menu submenu: David explicitly does not want items behind the paw icon.) Governs R1, R2.
- **Throws land on the real desktop, not inside the 720×480 panel.** (session-settled: user-approved — chosen over clamping the ball into the panel: "throw on the screen and the dog runs towards it" implies screen-scale travel.) Governs R7, R8.
- **v1 objects are ball, food bowl, water bowl.** Ball is the only object with new behavior; bowls reuse `interact(.eat)`/`interact(.drink)`. Governs R3, R10.

### Requirements

**Tray**

- R1. Moving the cursor into the notch region opens a tray that extends downward from the notch, visually continuous with it (black, rounded bottom corners), showing each object as a 2D sprite with a label. The paw menu gains no item entries.
- R2. The tray closes when the cursor leaves the tray and notch region for 400 ms, or when an item is picked. Opening never steals focus or activates the app.
- R3. The tray lists ball, food bowl, water bowl. A Mac without a notch shows the tray from a 200×6 pt hover strip at the top-center of the main display.

**Held item**

- R4. Clicking a sprite closes the tray and makes the cursor show that item's sprite everywhere on screen, over any app, until the item is thrown or cancelled.
- R5. Right-click, or re-entering the notch region, cancels the hold and restores the normal cursor without side effects.
- R6. While an item is held, left-clicks do not reach other apps.

**Fetch**

- R7. Left-clicking anywhere on the display that contains the pet panel throws the held ball toward that point; the ball lands on the dog's ground plane at the depth and lateral offset the click implies (higher on screen = farther away), clamped to the arena bounds.
- R8. After the throw the dog turns toward the ball, runs to it (`shiba_run_loop` with root motion), performs `shiba_fetch_pickup`, turns back, walks to its home spot with `shiba_fetch_carry_loop`, drops the ball on the ground in front of it, plays `shiba_happy`, then resumes autonomous behavior. The whole trip is visible across the desktop, the dog's on-screen size and home spot are unchanged from before the throw.
- R9. A ball lying on the ground can be clicked to pick it up again (cursor becomes the ball); it is removed 5 minutes after the last fetch ends, or when a different item is thrown.
- R10. Throwing a bowl starts the existing eat/drink interaction at the dog's current spot; the bowl sprite disappears from the cursor.
- R11. Any other interaction (pet, call, menu action) during a fetch cancels it: the ball stays where it is, the dog returns to `idle` where it stands, then walks home on the next autonomous tick.
- R12. A fetch counts as play for the needs model: `+100 fun`, `+20 affection`, and the awake-play energy drain, over the fetch's duration.

**Budget and safety**

- R13. Idle CPU stays at 0.0% when no tray, hold, or fetch is active; the tray window is not rendering continuously while collapsed.
- R14. Nothing in this feature requires Accessibility or Input Monitoring permission.

### Acceptance Examples

- AE1. Covers R1, R2: cursor enters notch → tray visible within 150 ms; cursor moves to the desktop → tray hidden after 400 ms; `NSApp.isActive` stays false throughout.
- AE2. Covers R4, R6, R7: click ball sprite → cursor is a ball over Finder; click Finder's desktop upper-left → no Finder selection change, ball arcs to a far-left landing spot, dog runs there.
- AE3. Covers R8: throw to top of screen → ball lands at the far clamp; dog shrinks with distance while running, returns to exactly the pre-throw pixel position and size, drops ball, `shiba_happy`, then `sit`.
- AE4. Covers R11: pet the dog mid-run → run stops within one frame, `shiba_pet_react`, ball remains at its landing spot and is clickable.
- AE5. Covers R5: hold ball, right-click → normal cursor, no throw, tray closed, no state change.

### Scope Boundaries

- Not in scope: drag-to-throw velocity, frisbee/rope/brush items, park walk mode, DS chrome and sounds, gaze/wander from `docs/ALIVENESS_PLAN.md` (fetch root-motion helpers should be reusable by it), ripped Nintendogs item icons (deferred; asset-only swap, see Open Questions).
- Not in scope: multi-display arenas. The overlay covers every display so clicks are captured, but throws are only accepted on the display that holds the pet panel; elsewhere the click is ignored and the item stays held.

### Open Questions

- Deferred, non-blocking: item art. U2 ships vector sprites drawn in SwiftUI (tennis ball with seam, two bowls). Ripping the Nintendogs item-icon sheet from Spriters Resource is a later asset-only swap through `ItemSprite`; it needs David's yes because it adds more copyrighted material to the private repo.

## Planning Contract

### Key Technical Decisions

- KTD1. **Notch tray is an `NSPanel` positioned over the notch rect.** Notch rect on the built-in screen: x from `screen.auxiliaryTopLeftArea!.maxX` to `screen.auxiliaryTopRightArea!.minX`, y from `screen.frame.maxY - screen.safeAreaInsets.top` to `screen.frame.maxY`. The panel is borderless, `nonactivatingPanel`, level `.statusBar`, `collectionBehavior [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`, `canBecomeKey == false`, backed by an `NSTrackingArea` with `mouseEnteredAndExited` and `activeAlways`. Collapsed size is the notch rect (content transparent, no rendering); expanded size grows downward with a `SwiftUI` `NSHostingView` tray. Fallback when no screen has `safeAreaInsets.top > 0`: same panel at a 200×6 pt strip at the top-center of `NSScreen.main`, level `.statusBar`. Chosen over a global `mouseMoved` monitor: the panel gets enter/exit for free and needs no permissions (R14). The cursor can travel into the notch area; that is how Clicky and similar apps work. Verify on David's machine first (stop condition).
- KTD2. **Sprites are SwiftUI views behind an `ItemSprite` enum** (`ball`, `foodBowl`, `waterBowl`) with `var cursorImage: NSImage` rendered once at 48×48 @2x via `ImageRenderer`. One place to swap art later.
- KTD3. **Held item = full-screen capture overlay per display.** `HeldItemOverlay: NSPanel` per `NSScreen`, borderless, transparent, `nonactivatingPanel`, `ignoresMouseEvents = false`, level `.popUpMenu`, `acceptsMouseMovedEvents = true`. `mouseMoved` calls `NSCursor(image:hotSpot:).set()`; `mouseDown` (left) reports the screen point to the app; `rightMouseDown` cancels. Non-activating panels cannot receive `keyDown`, and a global key monitor needs permission (R14), so Escape is not a cancel path; right-click and notch re-entry are (R5). Chosen over drawing a sprite that follows the cursor with a global monitor: that cannot block clicks reaching other apps (R6). Risk: `NSCursor.set()` from a non-key window. If the system arrow reasserts itself, add a `.cursorUpdate` tracking area on the overlay's content view and call `set()` from `cursorUpdate(with:)` as well.
- KTD4. **Fetch arena = the pet panel temporarily resized to the screen's `visibleFrame`, with the camera projection adjusted so the home mapping is pixel-identical.** Before expanding, record the home frame `F_h` (the autosaved panel frame). Expand to `F_a` (screen frame, since the panel is a floating non-activating window it may cover the menu bar area; clamp to `visibleFrame` if the notch/menu area causes artifacts). Set `cameraNode.camera!.projectionTransform = M · P_h`, where `P_h` is the projection SceneKit computed for `F_h` (read `projectionTransform` before expanding) and `M` maps NDC of `F_h` into NDC of `F_a`: `sx = F_h.width / F_a.width`, `sy = F_h.height / F_a.height`, `tx = (2·(F_h.midX − F_a.midX)) / F_a.width`, `ty = (2·(F_h.midY − F_a.midY)) / F_a.height`. Setting `projectionTransform` overrides `fieldOfView` until a camera property changes, so set it last. `SCNView.unprojectPoint` and `hitTest` honor it, so ground mapping (KTD6) needs no special casing. During the arena the panel sets `ignoresMouseEvents = true` (clicks pass to the desktop; petting is unavailable mid-fetch, which R11 tolerates via the menu path) and restores `F_h`, the default projection, and mouse handling when the fetch ends. Chosen over a second full-screen scene window (double-loads the model) and over moving the home to bottom-center (visible change to David's placement). Fallback if the matrix approach misbehaves: keep the arena at `visibleFrame` and move the dog's home to the ground point that projects to the panel's old center; report this to David as a visible change.
- KTD5. **`FetchSequence` lives in PetKit and is pure.** `struct FetchSequence` with `init(home: SIMD2<Double>, ball: SIMD2<Double>, clipDurations: (pickup: TimeInterval, happy: TimeInterval))`, `mutating func advance(by dt: TimeInterval)`, and read-only `phase` (`turnToBall`, `run`, `pickup`, `turnHome`, `carry`, `drop`, `celebrate`, `done`), `position`, `heading` (radians, +z toward camera), `clip` (`shiba_run_loop`, `shiba_fetch_pickup`, `shiba_fetch_carry_loop`, `shiba_happy`), and `ballAttached: Bool`. Speeds: run 2.2 units/s, carry 1.4 units/s, turns 0.2 s. Positions are x/z on the ground plane (y = 0). `PetActivity` gains `case fetch`; `PetBehavior.interact(.fetch, at:, duration:)` takes the sequence's total duration and applies R12 like `play`. Chosen over putting motion inside `SceneHost`: keeps timing deterministic and testable without SceneKit, matching the existing `PetBehavior` style.
- KTD6. **Screen point → ground point.** `SceneHost.groundPoint(forScreenPoint:) -> SIMD2<Double>?`: convert to view coordinates, `unprojectPoint` at z 0 and 1, intersect the ray with y = 0. Rays that miss the plane (above the horizon) are clamped along the ray's ground projection to `zMin = −8`. Lateral clamp `|x| ≤ 6`. The ball throw is an `SCNAction` custom action tracing a parabola from a launch point in front of the camera (world `(0, 0.9, 1.6)` in the home frame) to the landing point over `0.75 s`; the ball is an `SCNSphere(radius: 0.08)` with a two-tone tennis-ball material and its own blob shadow. Perspective handles apparent size.
- KTD7. **Root motion applies to `petAnchor`.** `SceneHost` gains `setPetPose(position: SIMD2<Double>, heading: Double)` and `attachBall(toMouth: Bool)` (ball parented under the `mouth` joint while `ballAttached`). Locomotion clips are in place by contract (`docs/ANIMATION_CONTRACT.md` line 98), so the app owns translation. The blob shadow is moved to be a child of `petAnchor` so it follows.

### High-Level Technical Design

```mermaid
sequenceDiagram
    participant U as David
    participant N as NotchTrayPanel
    participant O as HeldItemOverlay
    participant A as AppDelegate
    participant S as SceneHost / PetPanel
    participant K as PetKit (PetBehavior, FetchSequence)
    U->>N: hover notch
    N-->>U: tray with sprites
    U->>N: click ball
    N->>A: pick(.ball)
    A->>O: show overlays, cursor = ball
    U->>O: left-click at screen point
    O->>A: throw(at: point, on: screen)
    A->>S: enterArena(); ground = groundPoint(point)
    A->>K: interact(.fetch, duration)
    A->>S: throwBall(to: ground)
    loop 100 ms loop (existing)
        A->>K: sequence.advance(dt)
        A->>S: setPetPose(position, heading); play(sequence.clip)
    end
    K-->>A: phase == .done
    A->>S: leaveArena(); ball on ground at home
```

### Assumptions and Constraints

- The 100 ms loop in `App.swift` is coarse for locomotion; `FetchSequence.advance` is called from that loop, and `SceneHost` interpolates `petAnchor` with a 100 ms `SCNAction.move` per update so motion reads smooth at 30 fps.
- `AnimationController.play(_:careRequest:)` currently maps activities to clips. Fetch bypasses that mapping with `playClip(named:)` for each phase; `play(.idle)` is called at `.done`. The preview flag in `AppDelegate` must not be set by fetch.
- `shiba_run_loop` is 28 frames at 30 fps (0.93 s); at 2.2 units/s one cycle covers ~2 units, which reads plausibly for a 1-unit dog.
- `PetBehavior.init` already drops an in-progress momentary interaction on relaunch, so a fetch never resumes after a crash; the ball node is not persisted.

### Sequencing

U1 → U2 → U3 are the tray and cursor stack and can land before any fetch. U4 (arena) and U5 (PetKit sequence) are independent of each other and of U3. U6 depends on U3, U4, U5. U7 depends on U3 and U4. U8 last.

## Implementation Units

- U1. **Notch tray panel with hover open/close**
  - Goal: R1, R2, R3 (tray shell only; static placeholder content).
  - Files: `mac/Sources/Nintendogs/NotchTrayPanel.swift` (new), `mac/Sources/Nintendogs/App.swift` (create the panel in `applicationDidFinishLaunching`).
  - Approach: implement KTD1. `NotchTrayPanel.notchRect(on:)` static helper plus fallback strip. Collapsed state: panel frame = notch rect, content view hidden. Expanded: animate frame height to `notch + 96 pt` with `NSAnimationContext` 120 ms, show `NSHostingView<TrayView>`. Exit timer 400 ms cancelled on re-enter.
  - Test scenarios: on David's notch screen, hover opens and leaves close (AE1); Activity Monitor shows 0.0% while collapsed (R13); `NSApp.isActive` false after open (screenshot + `ps`).
  - Verification: `mac/scripts/bundle.sh release`, restart `nintendogs-native`, synthetic `CGEvent` mouse move into notch rect, `screencapture -x -o -l <tray window id>`.

- U2. **Item sprites and tray content**
  - Goal: R3, R4 (selection callback), KTD2.
  - Files: `mac/Sources/Nintendogs/ItemSprite.swift` (new), `mac/Sources/Nintendogs/TrayView.swift` (new), `NotchTrayPanel.swift`.
  - Approach: `enum ItemSprite: CaseIterable { case ball, foodBowl, waterBowl }` with `label`, `view: some View`, and cached `cursorImage` via `ImageRenderer(scale: 2)`. `TrayView` = horizontal row, 56 pt cells, hover highlight, `onPick: (ItemSprite) -> Void`. Picking closes the tray.
  - Test scenarios: three sprites render legibly on the black tray at 1x and 2x (screenshot); `cursorImage` is 96×96 px with transparent background (throwaway probe).
  - Verification: screenshot of expanded tray committed as `docs/screens/notch-tray.png`.

- U3. **Held-item cursor overlay**
  - Goal: R4, R5, R6, KTD3.
  - Files: `mac/Sources/Nintendogs/HeldItemOverlay.swift` (new), `App.swift` (`hold(_:)`, `cancelHold()`, `throwHeld(at:on:)` stubs), `NotchTrayPanel.swift` (notch re-entry cancels hold).
  - Approach: one overlay per `NSScreen`, created on hold and ordered out on release. Left click reports `(NSPoint, NSScreen)`; right click cancels. Overlays ignore clicks on screens other than the panel's screen (item stays held).
  - Test scenarios: AE2 first half (cursor is a ball over Finder, Finder does not receive the click), AE5.
  - Verification: synthetic `CGEvent` click on the desktop while holding; Finder selection unchanged (check via screenshot); Console shows no `TCC` prompts.

- U4. **Fetch arena: panel expansion with preserved home mapping**
  - Goal: R7 (ground mapping), R8 (unchanged size/spot), KTD4, KTD6.
  - Files: `mac/Sources/Nintendogs/PetPanel.swift` (`enterArena(on:)`, `leaveArena()`), `mac/Sources/Nintendogs/SceneHost.swift` (`groundPoint(forScreenPoint:)`, `applyHomeProjection(home:arena:)`, `restoreProjection()`, camera node kept as a property).
  - Approach: per KTD4. `enterArena` stores `frame` as `homeFrame`, sets `ignoresMouseEvents = true`, expands, applies the projection matrix. `leaveArena` reverses in the opposite order. Do not touch `setFrameAutosaveName` while expanded: call `setFrameAutosaveName("")` before expanding and restore after, so the arena frame is never autosaved.
  - Test scenarios: screenshot before and after `enterArena` with the dog idle: pixel position and bounding size identical within 1 px; `groundPoint` of the panel's old center returns `(0, 0)` ± 0.01; a point at the top edge returns `z == −8`.
  - Verification: throwaway `swiftc` probe that loads the app's `SceneHost` in an offscreen window and prints `groundPoint` for four corners; two window screenshots diffed with `argent-screenshot-diff` or a pixel-compare script.

- U5. **`FetchSequence` and `PetActivity.fetch` in PetKit**
  - Goal: R8 timing, R11, R12, KTD5.
  - Files: `mac/Sources/PetKit/FetchSequence.swift` (new), `mac/Sources/PetKit/Needs.swift` (`case fetch`), `mac/Sources/PetKit/Behavior.swift` (fetch duration parameter, R12 rates, cancellation path), `mac/Sources/PetKit/AnimationController.swift` (`profile(for: .fetch)` returns the idle profile; fetch phases use `playClip`), `mac/Tests/PetKitTests/FetchSequenceTests.swift` (new).
  - Approach: KTD5. Total duration = turn + run distance/2.2 + pickup clip + turn + carry distance/1.4 + drop 0.3 s + happy clip. `PetBehavior.interact(.fetch, at:duration:)`; `interact` with any other activity while `activity == .fetch` ends fetch (R11).
  - Test scenarios: deterministic phase sequence for a 4-unit throw; `position` ends at `home`; `heading` faces the ball during `run` and faces the camera during `carry`; `ballAttached` true only from end of `pickup` to `drop`; fetch applies `+100 fun` over its duration; interacting mid-fetch sets `activity == .idle`.
  - Verification: tests written to the `PetKitTests` conventions; while `swift test` is blocked, run the same assertions in a throwaway `swiftc` probe like the needs smoke.

- U6. **Scene-side fetch: ball, throw, root motion, clip routing**
  - Goal: R7, R8, R9, R11, KTD6, KTD7.
  - Files: `SceneHost.swift` (ball node, `throwBall(to:)`, `setPetPose`, `attachBall(toMouth:)`, ball click hit-test → `onBallPicked`, shadow reparent), `App.swift` (fetch driver in the 100 ms loop, `throwHeld` real implementation, 5-minute ball removal, cancel path calls `leaveArena`), `mac/Sources/PetKit/AnimationController.swift` if a public `isPlaying(clip:)` is needed for phase handoff.
  - Approach: on throw: `enterArena`, `groundPoint`, `interact(.fetch, duration:)`, `throwBall`. Each loop tick: `sequence.advance(dt)`, `setPetPose`, `playClip` on phase change, `attachBall` on `ballAttached` change. On `.done` or cancel: `leaveArena`, ball placed at `(0.35, 0, 0.3)` in front of the dog, `play(.idle)`.
  - Test scenarios: AE2, AE3, AE4; ball clickable after drop (R9); ball removed after 5 minutes (shorten via a debug constant in the probe, not in shipped code).
  - Verification: three window screenshots during one fetch (`docs/screens/fetch-{throw,run,return}.png`); `ps` CPU during fetch ≤ 15%, 0.0% again 10 s after it ends.

- U7. **Bowl items**
  - Goal: R10.
  - Files: `App.swift` (`throwHeld` for `.foodBowl` / `.waterBowl` → `interact(.eat)` / `interact(.drink)`).
  - Approach: no arena, no ground mapping; existing `showCare` bowl node is the visual.
  - Test scenarios: hold food bowl, click desktop → hunger decreases over the next seconds, cursor normal, existing eat clip plays.
  - Verification: needs percentages in the paw menu before/after (screenshot).

- U8. **Soak and docs**
  - Goal: R13, R14; README and Obsidian plan updated.
  - Files: `README.md` (feature list, permissions statement), `docs/ANIMATION_CONTRACT.md` (Mac-side consumer note: root motion now applied by the app for run/carry), Obsidian `projects/nintendogs-mac-pet-plan.md` (mark this plan's units).
  - Test scenarios: 10-minute idle soak with tray collapsed: CPU 0.0%, RSS stable; no TCC prompts in Console during the whole session.
  - Verification: `ps -o %cpu=,rss= -p <pid>` sampled at 0, 5, 10 min.

## Verification Contract

- Build: `DEVELOPER_DIR=/Library/Developer/CommandLineTools mac/scripts/bundle.sh release` from the repo root; must exit 0 and `codesign --verify` the bundle.
- Run: `hub start nintendogs-native` (existing supervised process) or restart; David has authorized launching this app.
- Screens: window ID via a `CGWindowListCopyWindowInfo` probe, `screencapture -x -o -l <id>`; synthetic input via `CGEvent` (mouse only; no key events, per R14).
- PetKit logic: `mac/Tests/PetKitTests/FetchSequenceTests.swift` under Swift Testing; until `swift test` is available (needs `sudo xcodebuild -license`), run the same assertions with a `swiftc -parse-as-library` probe over `mac/Sources/PetKit/*.swift`, then delete the probe.
- Budget gates: idle 0.0% CPU with tray collapsed; ≤ 15% during fetch; RSS under 120 MB.
- Git hygiene: `git diff --check` clean; commit on `feat/desktop-recreation`; no new files under `public/`.

## Definition of Done

- Global: R1–R14 observable in the running `.app`; AE1–AE5 reproduced with screenshots in `docs/screens/`; no permission prompts; paw menu unchanged except no item entries; probes and debug constants removed; `docs/plans/` plan untouched except by review.
- Per unit: the unit's test scenarios pass and its verification artifact exists.
- Cleanup: dead fallback branches from KTD4 (if the matrix approach ships) removed; no experiment code left behind.
- Acceptance: David confirms the tray feel and the fetch read on his notch MacBook; only he marks it shipped.

## Appendix

### Sources

- `mac/Sources/Nintendogs/SceneHost.swift` lines 9–10 (camera), 108–126 (`showCare` approach move), 128–167 (mouse handling to extend for ball pick).
- `mac/Sources/Nintendogs/PetPanel.swift` (panel flags, autosave name to suspend during arena).
- `mac/Sources/Nintendogs/App.swift` lines 51–71 (100 ms loop), 78–104 (`interact`, `refresh`).
- `mac/Sources/PetKit/Behavior.swift` header (rates and momentary-interaction semantics to mirror for fetch).
- `mac/Sources/PetKit/AnimationController.swift` lines 69–76 (clip names), 163–190 (`play`, `playClip`).
- `blender/CLIPS_RESULT.md` (clip frame counts: run 28, pickup 75, carry 40, happy 75 at 30 fps).
- `docs/ANIMATION_CONTRACT.md` line 98 (locomotion in place; app moves the root).
- `docs/ALIVENESS_PLAN.md` (wander/gaze plan; shares root-motion needs with this plan).
- Apple: `NSScreen.safeAreaInsets`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea` (macOS 12+); `SCNCamera.projectionTransform` overrides `fieldOfView`; `NSPanel` `nonactivatingPanel` cannot become key.
