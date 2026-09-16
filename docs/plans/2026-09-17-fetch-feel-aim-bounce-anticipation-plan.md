---
title: Fetch Feel - Aim, Bounce, Anticipation - Plan
type: feat
date: 2026-09-17
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-plan-bootstrap
execution: code
---

# Fetch Feel - Aim, Bounce, Anticipation - Plan

## Goal Capsule

- **Objective:** holding the ball feels like holding a ball and aiming with it; the throw reads as a real tennis ball that bounces and rolls to rest; the dog is visibly impatient while you hold it and launches the instant you throw, mouths the ball, and runs back toward you.
- **Means:** a deterministic `BallFlight` value type in PetKit (gravity, restitution, roll-out, arena bounds) replacing the fixed 0.75 s parabola; an aim state in `SceneHost` (ground marker, body yaw and head gaze tracking the cursor) active while the ball is held; a re-targetable `FetchSequence` whose chase begins at the throw and whose carry destination follows the cursor into the home region.
- **Authority:** this plan, then `docs/ANIMATION_CONTRACT.md` for clip semantics and rig limits, then `docs/plans/2026-09-16-notch-item-tray-fetch-plan.md` for the arena/projection decisions it settled.
- **Stop conditions:** stop and ask if (a) keeping the arena expanded for the whole hold breaks the 120 MiB RSS gate, or (b) the predicted rest point cannot be made to agree with the rendered ball (chase would aim at the wrong spot).
- **Execution profile:** single-machine Mac work in `mac/Sources`. One new Blender clip is requested from David and is optional at runtime until it lands.
- **Finish and ship:** implementer builds the `.app`, verifies hold/aim/bounce/chase/return with window screenshots and synthetic mouse input, commits on `feat/desktop-recreation`, and David accepts the feel.

## Product Contract

### Summary

Make the existing desktop fetch feel physical: the held ball aims, the thrown ball bounces and rolls, the waiting dog is excited, and the chase starts on the throw and ends back at the user.

### Problem Frame

The shipped loop is mechanically complete but reads as scripted. The cursor already becomes the ball sprite, but nothing in the dog's world acknowledges it — the dog keeps idling and wandering while you aim, and there is no indication of where the ball will land. The throw is a 0.75 s symmetric parabola that ends exactly at the click point with no impact, bounce, or roll (`SceneHost.advanceBallThrow`), so the ball reads as a tween rather than an object. The chase is gated behind landing (`AppDelegate.advanceFetch` only starts the sequence on the tick the ball lands), which inserts a dead beat where a real dog would already be running. The carry destination is the dog's pre-throw home spot (`FetchSequence.dropOffset` from `home`), so the return is toward a remembered point rather than toward the person who threw it.

### Key Decisions

- **Hand-rolled ballistics in a PetKit value type, not SceneKit physics.** (session-settled: user-approved — chosen over `SCNPhysicsBody`: the chase needs a rest point predicted at throw time, and the sequence must stay deterministic under the app's variable-`dt` loop.) Governs R4, R5, R11.
- **The dog launches at the throw toward the predicted rest point and re-targets as the ball settles.** (session-settled: user-approved — chosen over waiting for the ball to stop, which is today's behavior.) Governs R8, R9.
- **The carry destination follows the cursor, clamped into the home region.** (session-settled: user-approved — chosen over the fixed home spot.) Governs R10.
- **The excited state is one new authored loop plus live code-driven gaze.** (session-settled: user-approved — chosen over composing it from existing tail-wag/beg/alert clips only; those are either sit-posture or one-shots.) Governs R2, R3.
- **Aiming expands the arena for the duration of the hold.** Governs R1, R6.

### Requirements

**Aim**

- R1. While the ball is held, the pet panel is expanded to the arena with the home mapping preserved, so the dog's on-screen size and spot do not change when the tray hands over the ball.
- R2. While the ball is held, the dog stops wandering, turns its body toward the ground spot under the cursor, and tracks that spot with its head within the authored gaze limits. Aim tracking follows the cursor anywhere on the display, not only inside the home panel.
- R3. While the ball is held, the dog plays an excited standing loop (tail wag, head up). The clip is `shiba_anticipate_loop` when present; until David authors it, the standing `shiba_look_around_loop` stands in and the app must not fail to launch because the new clip is absent.
- R4. A faint ring marks the ground spot the ball would land on, positioned at the same point the throw will use, and it disappears the moment the ball leaves the cursor or the hold is cancelled.
- R5. Cancelling the hold (right-click or notch re-entry) removes the marker, returns the panel to its home frame, and resumes autonomous behavior with no ball in the scene.

**Flight**

- R6. A throw launches the ball on a ballistic arc whose first impact is the aimed ground spot; the ball then bounces with tennis-ball restitution, loses horizontal speed on each impact, rolls out, and comes to rest. Rest is reached within the arena bounds; a ball that would leave them stops at the boundary.
- R7. The ball's altitude reads on the ground: its shadow tracks its ground position, and shrinks and fades with height. The ball spins in the direction it travels and squashes briefly on each impact.

**Chase and return**

- R8. The dog starts running at the throw, not at the landing: the chase target is the rest point predicted at launch, and it re-targets as the ball bounces so the dog ends up where the ball actually stops.
- R9. If the dog reaches the ball before it settles, it watches the ball instead of picking it up, and picks it up once the ball is at rest.
- R10. After pickup the dog turns and carries the ball toward the ground spot under the cursor, clamped into the region visible in the home panel, drops it in front of itself there, and celebrates. The dog's final spot is always inside the home panel.
- R11. A fetch still counts as play for the needs model, using the trip duration estimated at throw time.
- R12. Any interaction during a fetch still cancels it: the ball stays where it is and the dog returns to idle where it stands.

**Budget and safety**

- R13. Idle CPU stays at 0.0% with no tray, hold, or fetch active, and resident memory stays under 120 MiB through a hold-aim-throw-fetch cycle.
- R14. No new permissions. Aim reads the cursor with `NSEvent.mouseLocation` polling on the existing app loop, as presence already does.

### Success Criteria

- Aiming, bouncing, and the immediate chase are legible in screenshots taken from the running app.
- The predicted rest point and the rendered resting ball agree, verified numerically, so the chase never runs to the wrong spot.
- David accepts the feel.

### Scope Boundaries

In scope: `BallFlight`, `FetchSequence`, `SceneHost` ball/aim/gaze, `AppDelegate` hold and fetch flow, one optional new clip, the animation contract note for it.

Out of scope:

- Drag-and-release throw gestures or throw-strength control. A click still throws, and strength is implied by distance.
- Ball-to-dog or ball-to-bowl collision.
- Multiple balls, or any other item gaining physics.
- Sound.

#### Deferred to Follow-Up Work

- A dedicated `shiba_fetch_drop` clip; the carry loop's final pose still covers the drop beat.
- Barking while impatient (`shiba_bark` exists but stacking a one-shot over the anticipation loop needs ambient-director scheduling work).

## Planning Contract

### Key Technical Decisions

- **KTD1. `BallFlight` is a pure PetKit struct advanced in fixed 1/240 s substeps.** The app's loop delivers variable `dt` (100 ms active tick, clamped), so a fixed substep is what makes the flight reproducible and makes the predicted rest point *exactly* equal to the simulated one: prediction is the same struct advanced to rest on a copy. Restitution 0.62, tangential damping 0.9 per bounce, roll deceleration 1.6 m/s², bounce-to-roll threshold 0.55 m/s vertical, rest threshold 0.06 m/s.
- **KTD2. First impact lands on the aimed point.** Launch solves for the vertical speed that puts the ball at ball radius after a distance-scaled flight time, so the aim marker stays truthful; everything past the first impact is emergent.
- **KTD3. Arena bounds live in the flight model.** `BallFlight.Bounds` carries the same `arenaXLimit`/`arenaZNear`/`arenaZFar` clamps `SceneHost.groundPoint` already applies; a component that would cross a bound is zeroed at it, inside the substep, so prediction and simulation cannot disagree.
- **KTD4. `FetchSequence` becomes stateful in position and heading.** Today position is a lerp between fixed endpoints, which cannot absorb a moving target. Position and heading are integrated per substep toward live targets (`updateBall`, `updateReturn`), heading eased on the shorter arc. Phases become `chase, watch, pickup, turnHome, carry, drop, celebrate, done` — `turnToBall` is gone because the dog now turns while running.
- **KTD5. The home region is computed from the home frustum, not the live view.** `SCNView.projectPoint`/`unprojectPoint` ignore the arena projection override (already documented on `SceneHost.Frustum`), so the existing `walkableXRange` cannot answer "is this point visible in the home panel" while expanded. `SceneHost` retains the home rect passed to `applyHomeProjection` and derives the region from the symmetric home frustum with its own ray math.
- **KTD6. The excited clip is optional at load time.** `AnimationController` gains an optional-clip list: missing files are skipped instead of throwing `missingAssets`, and only optional names may be absent. This is what lets David drop `shiba_anticipate_loop.dae` into `mac/Assets/shiba/clips/` with no code change.
- **KTD7. Aim gaze reuses the existing additive head constraint.** Body yaw does the large rotation; the head stays inside the authored ±20° yaw / ±10° pitch caps, so the rigid-skinning rule in `docs/ANIMATION_CONTRACT.md` still holds.

### Assumptions

None outstanding; the scope was confirmed in session before writing.

## Implementation Units

### U1. `BallFlight` in PetKit

`mac/Sources/PetKit/BallFlight.swift` (new). Gravity/restitution/roll model per KTD1-KTD3, `init(launch:aim:bounds:)`, `advance(by:)`, `position`, `groundPosition`, `isAtRest`, `bounceCount`, `predictedRest`. No SceneKit import.

Acceptance: a probe shows first impact within 1 mm of the aim point; `predictedRest` equals the position after advancing to rest; a ball aimed past `arenaXLimit` rests on the limit.

### U2. `SceneHost` flight, shadow, spin, squash

Replace `ballThrow` with `BallFlight`. `throwBall(to:)` returns the predicted rest point. `advanceBallFlight(by:)` returns rest/bounce state. Shadow scales and fades with height; ball spins about the axis perpendicular to travel; a bounce triggers a short squash.

Acceptance: screenshots show a bounce; ball comes to rest with shadow at full opacity and scale 1.

### U3. Aim state in `SceneHost`

`setAimTarget(_:)` positions and shows a ground ring, and drives body-yaw easing plus head gaze at that spot; `clearAimTarget()` hides it. `homeRegionClamp(_:)` implements KTD5.

Acceptance: with an aim target set outside the home panel, the dog faces it and the ring renders at the same ground point a throw would use.

### U4. Re-targetable `FetchSequence`

KTD4. New phases, integrated position/heading, `updateBall(position:atRest:)`, `updateReturn(to:)`, `estimatedDuration`. `mac/Tests/PetKitTests/FetchSequenceTests.swift` is rewritten against the new contract; the old phase-boundary table pins the removed lerp timing and goes away with it.

Acceptance: probe shows the dog chasing a moving ball to its final rest point, waiting when it arrives early, and ending at a live return target.

### U5. App flow: hold-aims, throw-launches

`AppDelegate`: `hold(.ball)` enters the arena and starts the aim/excited state; the loop advances aim while holding; `throwHeld` clears aim and starts flight and chase together; `advanceFetch` advances flight and sequence in the same tick and feeds live ball and return targets; cancel paths restore the panel.

Acceptance: full cycle verified on the running app with synthetic mouse input; cancel during hold and during fetch both restore the home panel and idle behavior.

### U6. Optional clip loading and contract note

`AnimationController.optionalClipNames` per KTD6 with posture metadata for `shiba_anticipate_loop`; `docs/ANIMATION_CONTRACT.md` gains the clip's row and authoring requirements.

Acceptance: app launches with the clip absent (stand-in used) and picks it up when present.

## Clip Request for David

One clip, authored against the existing rig contract (rig faces `+Z`, in-place, all 28 joints keyed, `_loop` suffix means it repeats, 0.25 s blend in/out):

- **`shiba_anticipate_loop`** — standing, weight forward, head up and slightly tilted as if watching a held ball, tail wagging fast, small weight shift or paw lift. 1.5-2.5 s, seamless loop, starts and ends in the standing idle pose so it blends from and to `shiba_idle_loop`. No root translation.

Nothing else is required. The pickup, carry, run, and happy clips already cover the rest of the trip, and the drop beat reuses the carry loop's final pose.
