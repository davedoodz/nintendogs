# Aliveness — autonomous desktop Shiba

## Outcome and status

The dog should look alive without selecting animations. Care remains optional interaction, not the trigger required to make it move.

**Built:** autonomous fidgets, posture changes, bounded wandering, cursor gaze and hover reactions, direct play gestures, fetch, daytime naps, return greetings, morning/evening rhythms, mood-driven expression layers, the 34-clip storyboard set, and a system-wide whistle key.

**Needs David's eye:** pace, character, and how enjoyable the interactions feel. Headless verification does not constitute visual acceptance or shipping.

## Architecture

- `PetBehavior` owns needs, care activities, and persisted presence history.
- `AmbientDirector` chooses visual actions using a seeded RNG, needs, local hour, cooldowns, and foreground elapsed time. It does not alter needs or persist its animation state.
- `AnimationController` owns clip metadata, posture routes, fades, logical request identity, scoped reactions, and locomotion. Repeated care-loop refreshes do not restart animations.
- `SceneHost` owns root travel, gaze, bounds, shadow, and hit-testing. `ExpressionAnimator` owns the lock-bridged additive face, tail, breathing, ear, and weight-shift constraints. `AppDelegate` coordinates these layers and workspace notifications.

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

The imported rig faces **+Z**: head/mouth positions established this in a bundled probe. Initial facing is toward the camera. Turning uses that same convention. Wander targets span depth −2.2…0.1 (the near end is where the front paws still clear the panel's bottom edge; at the far end the dog renders at about half size), so legs toward or away from the camera read as real depth. Bounds account for the model's horizontal radius and camera perspective at the current depth, not just its center. The panel keeps a 3:2 aspect ratio when resized. The shadow follows the pet anchor. A hungry/thirsty dog can wander toward the bowl.

## Attention and play

- Hover: alert, then a happy response; sustained attention slowly increases affection.
- Cursor nearby: limited, eased head aim, composited from each frame's authored animation pose. The SceneKit transform constraint is explicitly non-incremental so a held gaze cannot compound into a full head rotation. Head position is preserved, and body-adjacent joints are not distorted.
- Single-click the dog: call/wake.
- Stroke across it: pet.
- Double-click it: play.
- Cursor leaves after attention: look around.

Cursor location is polled without a global input monitor or Accessibility permission. Gaze is disabled during sleep, eating, drinking, and diagnostic preview. The animation picker remains under **Animation diagnostics**; it is not needed for normal use. **Personality** controls activity level and whether the dog explores the panel.

Expression is layered independently from the authored body clip. `PetExpression` maps needs, immediate activity, direct/recent engagement, and locomotion into calm/content/excited/alert/low/asleep targets. `ExpressionAnimator` composes non-incremental constraints on `tail2`, `tail3`, `chest`, `spin`, `waist`, both ears, and the mouth. Tail carriage, right-biased social wag, breathing, ear flicks, weight shifts, jaw panting, and tongue movement therefore continue while the body changes clips. Tail layering yields to clips that explicitly own the tail. Fast wag/pant states request a 30 Hz loop; passive content stays below 2 Hz with no pant so idle redraws remain at 10 Hz. A nearby cursor alone no longer promotes lifelong high affection into a permanent 30 Hz pant; direct hover or recent interaction is required.

The eye material has coat-specific open/closed/squint/wide 32×32 textures. Petting closes the eyes and opens the jaw before showing a procedural tongue plane parented to the mouth joint; sleep closes the eyes and hides the tongue. Blinks run at randomized 3–7 second intervals when no state forces an eye expression. A carried fetch ball suppresses procedural jaw pant and tongue motion so the mouth anchor stays stable.

The storyboard's ten third-tier clips are wired into explicit interaction choreography. Petting hands `shiba_pet_react` into `shiba_pet_head_loop`; three strokes within four seconds or sustained petting settles through `shiba_pet_settle` into side rest, another stroke selects `shiba_belly_loop`, and five seconds without petting rises through `shiba_lie_side_up`. Call plays stun → curious orientation → a real root-motion run toward the near position → paws-up entry/loop → paws-down into sitting. Choreography uses the same posture metadata and preloaded players as ordinary activity routing.

That call choreography is also bound to a whistle key, `⌥⌘W`, so the dog can be called while its back is turned and while another app is focused. The panel does not activate and receives no `keyDown`, and the app has no main menu whose key equivalents could fire in the background, so the key is a Carbon `RegisterEventHotKey` registration rather than an `NSEvent` global monitor: the monitor route would require the user to grant Input Monitoring, and this route requires no permission. A modifier-free key was deliberately not used, because it would take that key away from every other app. Whistling at a hidden dog shows the panel first, since the choreography advances from the presence loop, which idles while the panel is hidden. If another app already owns the combination, registration fails and the menu reports it instead of leaving a key that silently does nothing.

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

The original aliveness soak checks all 24 base/tier-2 clips actually changing bone transforms; viewport-edge pixels throughout the recording; root travel; pause/resume; posture routes; queued-walk cancellation; sustained play; sleep/stir/return; greeting/care preemption; and preview isolation. Separate headless input checks cover real hit-testing, click, double-click, and strokes. Gaze checks verify left/right/up/down direction and an unchanged head-joint origin. Persistence checks cover feeding 80 → 50, JSON reload, legacy saves, and backward clocks.

The first directional gaze snapshots did not exercise SceneKit's frame-to-frame constraint evaluation and missed a live cumulative head-spin defect. The corrected proof renders 3,600 continuous Metal frames with a held cursor, changing body yaw, 30 Hz scene updates, 60 Hz rendering, a sleeping neutral interval, and a stopped-animation interval. The gaze remained within **20.713°**, returned to **0.040°** during sleep, and moved the head joint origin by **0.000000**. A focused SceneKit reproduction measured the unsafe default at **60° after twelve 5° frames** versus **5°** with non-incremental evaluation. Evidence: `mac/build/gaze-spin-proof/metal-after/`.

The final expression proof loads the bundled coat-B model and production textures, installs all eight additive constraints, and renders 540 Metal frames across petting, ball carry, calm blinking, and sleep. It verifies all four eye textures load; a randomized open-eye blink closes and reopens; the closed-eye image reaches the eye material; the tongue shows for petting and hides for sleep and ball carry; carried-ball jaw pant is suppressed; call root travel reaches its target; and the petting tail delta stays anatomically bounded at **15.05°**. A 10-second, 30 Hz high-expression render used **0.37 CPU-seconds over 11.85 wall-seconds** (about **3.1% CPU**) with a **69.8 MiB** maximum resident set.

A second bundled Metal probe initializes the production controller with all **34** clips, renders each clip without a load/channel failure, and exercises the runtime handoffs into `shiba_pet_head_loop`, `shiba_call_curious`, `shiba_paws_up_loop`, and `shiba_sit_idle_loop`. Evidence: `mac/build/expression-proof/verification.json` and `mac/build/clip-integration-proof/verification.json`.

The whistle proof asserts the registration is live at the OS rather than a silent no-op: a second claim on `⌥⌘W` is refused while the key is held, and succeeds again after `invalidate()`, which is what proves the key is released instead of left dead for every app. It then starts the dog back-turned and far away and drives the call beats, confirming the head turns toward the viewer during orientation and that the dog runs from **z −2.20 to 0.27** while its facing goes from **3.14 to 0.00 radians**, over 391 frames at 30 Hz. A synthetic `⌥⌘W` key event was deliberately never posted: it would have been delivered to whatever app the user had focused, where that combination closes other tabs in Safari and Chrome. Physical key delivery is therefore the one link left for David to confirm by pressing the key. Evidence: `mac/build/whistle-proof/verification.json`.

A 60-second real-time offscreen render of the broader aliveness system at 720×480 with 4× MSAA measured **2.55% CPU**, averaging **27.2 fps** on the current M2 Max. The expression-specific 30 Hz measurement above excludes 4× MSAA. Both are offscreen rendering measurements, not long-duration live-window soaks or battery-life guarantees. The old static scene's 0.0% CPU result is not an animation-performance claim.

Swift Testing execution remains blocked by the local Xcode/Command Line Tools runtime/license state. Focused regression sources are retained; their syntax and the release build are checked, and the same risky transitions are exercised by bundled executables.

## Outside this change

Park walking and other roadmap work remain separate. Concurrent fetch work and the returned Blender clip stack were preserved as distinct commits. No visible app restart, visual acceptance, distribution, or shipping is implied by the headless checks.
