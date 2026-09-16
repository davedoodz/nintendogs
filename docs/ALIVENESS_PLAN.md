# Aliveness — autonomous desktop Shiba

## Outcome and status

The dog should look alive without selecting animations. Care remains optional interaction, not the trigger required to make it move.

**Built:** autonomous fidgets, posture changes, bounded wandering, cursor gaze and hover reactions, direct play gestures, daytime naps, return greetings, and morning/evening rhythms. All use the existing 24 Blender clips; no new Blender exports were needed.

**Needs David's eye:** pace, character, and how enjoyable the interactions feel. Headless verification does not constitute visual acceptance or shipping.

## Architecture

- `PetBehavior` owns needs, care activities, and persisted presence history.
- `AmbientDirector` chooses visual actions using a seeded RNG, needs, local hour, cooldowns, and foreground elapsed time. It does not alter needs or persist its animation state.
- `AnimationController` owns clip metadata, posture routes, fades, logical request identity, scoped reactions, and locomotion. Repeated care-loop refreshes do not restart animations.
- `SceneHost` owns root travel, gaze, bounds, shadow, and hit-testing. `AppDelegate` coordinates these layers and workspace notifications.

## Fidgets and posture

While awake, the dog alternates idle and looking-around loops, with occasional yawns, shakes, alerts, barks, and happy reactions. It occasionally sits, breathes in its sitting loop, scratches, and stands again. Low energy favors yawning; low cleanliness favors shaking/scratching; happy needs favor happy reactions. Evening increases yawning; nighttime reduces standing activity.

Flourishes have a six-second minimum gap and per-clip cooldowns. Care, requested rest, and diagnostic preview take priority. Completing care leaves a short settling interval before spontaneous activity resumes. Cancelling an interaction also cancels queued ambient sequences.

Actual authored postures take precedence over the original draft's assumptions:

- `shiba_scratch` and `shiba_beg_loop` are seated.
- `shiba_yawn`, bark, alert, shake, happy, and looking-around are standing.
- `shiba_stretch` moves from lying to standing.
- Sleeping may briefly stir through wake and lie-down, then return to sleep.

## Wandering

Walk/run clips have fixed roots. Root movement waits until the actual gait clip starts; a standing-up route never translates the dog prematurely. Travel stops on care, hiding, or suppression, and ending a gait routes back to the logical resting posture.

Speeds are measured from the backward velocity of the planted hind paw in the authored Collada matrices, scaled to the normalized model. Malformed or missing gait data raises a loading error rather than silently substituting guessed speeds.

The imported rig faces **+Z**: head/mouth positions established this in a bundled probe. Initial facing is toward the camera. Turning uses that same convention. Bounds account for the model's horizontal radius and camera perspective, not just its center. The panel keeps a 3:2 aspect ratio when resized. The shadow follows the pet anchor. A hungry/thirsty dog can wander toward the bowl.

## Attention and play

- Hover: alert, then a happy response; sustained attention slowly increases affection.
- Cursor nearby: limited, eased head aim, composited after authored animation. Head position is preserved, and body-adjacent joints are not distorted.
- Single-click the dog: call/wake.
- Stroke across it: pet.
- Double-click it: play.
- Cursor leaves after attention: look around.

Cursor location is polled without a global input monitor or Accessibility permission. Gaze is disabled during sleep, eating, drinking, and diagnostic preview. The animation picker remains under **Animation diagnostics**; it is not needed for normal use. **Personality** controls activity level and whether the dog explores the panel.

## Presence rhythm

After twenty minutes alone during the day, the dog settles into sitting; after twenty-five, it naps. A forty-five-minute cycle lets a fully rested unattended dog get up again rather than sleep forever. Critical hunger/thirst prevents this nap. Calling or caring wakes it and provides an awake grace period.

System/display/session return notifications request a greeting, with duplicate notifications debounced. Requested rest is respected. Morning return favors a stretch on the wake route and adds a shake before the alert/happy greeting. `lastInteractionAt` is persisted; older saves without it load using their saved timestamp.

Hidden or sleeping workspaces do not advance the visual clock. Needs still use wall-clock catch-up. The foreground animation loop targets 30 Hz and backs off to 250 ms while inactive.

## Optional sound

Not implemented. The available audio inventory contains interface/reaction sounds, not identified bark/yawn/shake recordings. Unrelated UI effects are not used as substitute dog vocals. Sound can be added once suitable recordings are identified and David hears them.

## Verification

Bundled, windowless probes exercise the actual PetKit code, SceneHost, and AppDelegate frame coordinator without ordering a window on screen or posting input to the desktop. The app harness changes only access control, its executable entry annotation, and the save destination; runtime methods are unchanged.

Evidence in `mac/build/aliveness-proof/`:

- `unattended-ten-minutes.mp4`: 600 seconds of accelerated foreground simulation, rendered at 10 recording frames/second from 30 Hz simulation.
- `transitions.txt`: autonomous clip changes; the verified run used 13 distinct clips and 20 distinct thirty-second behavior windows.
- `unattended-10s.png`, `unattended-60s.png`, `unattended-300s.png`: representative frames.

Checks cover all 24 clips actually changing bone transforms; viewport-edge pixels throughout the recording; root travel; pause/resume; posture routes; queued-walk cancellation; sustained play; sleep/stir/return; greeting/care preemption; and preview isolation. Separate headless input checks cover real hit-testing, click, double-click, and strokes. Gaze checks verify left/right/up/down direction and an unchanged head-joint origin. Persistence checks cover feeding 80 → 50, JSON reload, legacy saves, and backward clocks.

A 60-second real-time offscreen render at 720×480 with 4× MSAA measured **2.55% CPU**, averaging **27.2 fps** on the current M2 Max. This is an offscreen rendering measurement, not a long-duration live-window soak or a battery-life guarantee. The old static scene's 0.0% CPU result is not an animation-performance claim.

Swift Testing execution remains blocked by the local Xcode/Command Line Tools runtime/license state. Focused regression sources are retained; their syntax and the release build are checked, and the same risky transitions are exercised by bundled executables.

## Outside this change

Fetch depth, park walking, and other roadmap work are separate. Unrelated concurrent UI work is preserved. No visible app restart, visual acceptance, distribution, or shipping is implied by the headless checks.
