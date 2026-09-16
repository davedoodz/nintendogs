# Clip sets: accepted base tier and second-tier authoring results

The 12 base clips below were accepted by the user before second-tier authoring.
The storyboard pass below rebuilds walk/run/carry; other accepted pose functions
remain unchanged in that pass. Later tiers are documented after the base-tier
rebuild instructions. Blender-side changes require renewed Mac playback review.

All files are in `mac/Assets/shiba/clips/`. All use 30 fps, one action per DAE,
sampled matrix transforms at every frame, unit scale 1 and the contract's
native Collada export settings. `shiba_clips.blend` contains the 12 named actions
for editing; its active action is `shiba_idle_loop`.

| Clip | Frames | Motion |
| --- | ---: | --- |
| `shiba_idle_loop` | 120 | Gentle chest/head breathing, staggered ear flick |
| `shiba_sit` | 60 | Stand to seated; folded knees/hocks, held ending |
| `shiba_sit_idle_loop` | 120 | Seated breathing, small head turn and ear flick |
| `shiba_lie_down` | 75 | Seated to lying; elbows and distal hind legs fold |
| `shiba_sleep_loop` | 150 | Head-rest pose and slow breathing |
| `shiba_eat_loop` | 90 | Head lowered, four jaw-chewing cycles |
| `shiba_walk_loop` | 40 | Lateral four-beat, 0.65 duty, linear stance, vertical bob |
| `shiba_run_loop` | 28 | Diagonal pairs, 0.55 duty, larger steps and suspension |
| `shiba_bark` | 60 | Two jaw openings with head/ear recoil; neutral ending |
| `shiba_fetch_pickup` | 75 | Head dip, jaw opens then closes, head returns |
| `shiba_happy` | 75 | Horizontal distal tail wag, two small bounces |
| `shiba_stretch` | 105 | Lying to foreleg extension to standing; held ending |

## Rigid-skinning constraints

`tail1` is stationary throughout all 12 clips. The six body-adjacent joints
stay at or below 7 degrees; their rotations are checked on every frame. The
larger movements use `tail2`/`tail3`, `head`, knees, elbows, hocks and paws.
Root motion for sit/lie/stretch moves the whole dog, preserving the torso joins.
Walk and run translate the root vertically only and never rotate it. Their two-link foot solver
reserves a bend at the knee/elbow to avoid a straight-limb snapping artifact.

Non-locomotion poses receive a whole-rig vertical correction when needed to
keep the lowest vertex at or above the original standing mesh's floor. No bones
are re-parented, no transforms are applied, and no weights/UVs/materials change.

## Export compatibility

The source-basis conversion introduced with the revised tail2 test is used for
all clips: sampled Blender poses are expressed in the original DAE joint bases,
and source geometry, controllers, inverse binds, materials and hierarchy are
retained exactly. Final files explicitly declare Y_UP. Details and the formula
are in `STEP0_RESULT.md` and `clip_pipeline.py`.

Constant matrix channels are retained for all 28 joints in the 12 state clips.
This is essential for seated/lying holds and resetting joints animated by an
earlier state. Keep Flat Curves is enabled for this purpose; Keep Keyframes
remains off and the action is still sampled at rate 1. The test wag remains a
single `tail2` channel. Each final file contains only its own action.

## Validation

- `clips_validation.json`: exact export arguments, all 28 channels, maximum
  body-adjacent rotation, loop closure, unchanged geometry/skin and state poses.
- `clips_roundtrip_validation.json`: every authored frame checked for floor
  penetration and abrupt joint steps; five poses per clip checked against a
  fresh DAE import. Maximum vertex mismatch is under 0.000003 source units.
- All six loops have matching first/last poses. Sit → sit_idle → lie_down →
  sleep → stretch → idle handoffs match on all 28 matrices.
- Rendered key poses were reviewed for all clips. Four retained reference
  renders are in `previews/`; a rebuild also makes 36 QA images in `qa_frames/`.

The sleeping clip uses the source eye texture: there is no eyelid joint in this
rig. This is an armature-only animation set, so it does not add a closed-eye
texture swap. Final seam appearance and state playback still need the Mac-side
SceneKit capture. These Blender checks do not claim Mac acceptance.

## Rebuild and verify

From the repository root:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 4.2\blender.exe' --background --factory-startup --python-exit-code 1 --python blender/author_clips.py
& 'C:\Program Files\Blender Foundation\Blender 4.2\blender.exe' --background --factory-startup --python-exit-code 1 --python blender/verify_clips.py
```

Append `-- --no-render` to the authoring command to skip QA renders. Native
intermediate exports and QA frames are ignored by Git and can be regenerated.
Only `blender/` and `mac/Assets/shiba/clips/` were edited.

## Second tier: 12 additional clips

`shiba_clips_tier2.blend` contains only the 12 new actions. The active action is
`shiba_stand_from_sit`; accepted states are referenced from their existing DAE
files for every non-loop entry and handoff check. The contract's Clip list was
extended to 24 entries in the same commit as these assets.

| Clip | Frames | Loop | Motion / handoff |
| --- | ---: | --- | --- |
| `shiba_stand_from_sit` | 45 | no | Seated → held idle first frame |
| `shiba_sit_from_lie` | 60 | no | Lying → held sit_idle first frame |
| `shiba_wake` | 60 | no | Head lifts, staggered ear flick, rise → sit_idle |
| `shiba_beg_loop` | 90 | yes | Seated, upward head tilt, two small head bobs |
| `shiba_yawn` | 60 | no | Slow wide jaw opening, head back, close → idle |
| `shiba_scratch` | 75 | no | Seated head tilt and distal hind-paw strokes → sit_idle; limited reach |
| `shiba_look_around_loop` | 150 | yes | Head turns left, holds, right, holds, returns |
| `shiba_drink_loop` | 60 | yes | Head down, six fast small jaw laps |
| `shiba_alert` | 30 | no | Ears lift, quick head turn toward viewer → idle |
| `shiba_pet_react` | 75 | no | Head tilt, ears fold back, distal yaw wag → idle |
| `shiba_shake` | 45 | no | Four shake waves with small opposing chest/waist yaw → idle |
| `shiba_fetch_carry_loop` | 40 | yes | Accepted walk cycle, lifted head, closed mouth |

All six constrained joints stay below 7° on every sampled frame; the measured
maximum in this tier is approximately 5°. `tail1` stays stationary. Carry's
root shares the walk's vertical bob, and all channels except head/mouth match walk.
Drink has six laps in 60 frames, versus eat's four chews in 90 frames.

### Scratch reach limitation

Literal hind-paw-to-ear contact was not achieved while keeping the hip under
7°. `shiba_scratch` therefore uses a seated ear-itch gesture: head tilted toward
the raised leg, repeated distal paw strokes and an ear response. It reads as a
scratch gesture, but the paw stops short of the ear; do not treat it as a verified
ear-contact animation. The hip is held to 5° instead of breaking the constraint.
`previews/shiba_scratch.png` makes this limitation reviewable on Mac.

The rig has no tongue or eyelid joint, so drinking is represented by jaw lapping
and yawn/sleep keep the existing eye texture. No material/texture behavior was
added. The shake stays subtle at torso joins: chest yaw is at most 2° and waist
yaw at most 1.8°, with the larger motion in the head and ear joints.

### Second-tier verification and previews

`verify_clips.py -- --tier2` checks all 12 frame counts, 28 channels, the strict
joint limit, floor contact, key continuity and fresh DAE reimport. All four loops
close; all eight non-loop entry/final poses match the specified accepted states.
The largest fresh-import vertex discrepancy is below 0.000003 source units.
Results are in `tier2_validation.json` and `tier2_roundtrip_validation.json`.
The first report also records hashes proving the accepted clip files were not
changed. Quaternion signs are made continuous when a distal joint crosses 180°
so between-frame interpolation cannot introduce a spin.

Retained renders cover `sit_from_lie`, `beg_loop`, `shake`, `pet_react`, and the
limited `scratch` pose. Two additional shake frames show opposing motion. A
rendered rebuild creates four QA frames per new clip in ignored `qa_frames/`.

```powershell
& 'C:\Program Files\Blender Foundation\Blender 4.2\blender.exe' --background --factory-startup --python-exit-code 1 --python blender/author_clips.py -- --tier2
& 'C:\Program Files\Blender Foundation\Blender 4.2\blender.exe' --background --factory-startup --python-exit-code 1 --python blender/verify_clips.py -- --tier2
```

Add `--no-render` after `--tier2` to skip authoring previews. Export arguments and
source-basis conversion are unchanged from the accepted pipeline. Constant pose
channels are retained for holds and state resets. Mac playback review of this
second tier remains pending. Changes are confined to `blender/`, the clips
directory, and the explicitly requested contract-table update.

## Storyboard gait rebuild

Walk and carry now use LH/LF/RH/RF swing offsets 0/.25/.50/.75, 0.65 duty,
fore/hind stride .17/.23 and lift .10/.13. Run uses diagonal offsets 0/.5,
0.55 duty, stride .24/.32 and lift .16/.20. The two-link IK and 0.96 bend
reserve remain; targets undo the torso transform before solving, and use
toe-mesh clearance to keep the pivot above the floor during toe-down/toe-off.
Body, ear, head and tail motion follow the storyboard; the tail base is still.
Carry is rebuilt from this walk, differing only on head and mouth channels.

The root-basis probe measured `(0, -0.610000014, 0)` for SIT's source offset:
Y is vertical, mapping to Blender world Z. Exported horizontal root range is
exactly zero. Vertical range is .019983053 for walk/carry and .059870958 for run.
Maximum gait seam angle is approximately 6 degrees (run); walk/carry are 4.
No export limit or verifier assertion was relaxed.

Independent exported `skl_root/waist/Lleg1/Lleg2/Lfoot1/Lfoot2` composition,
using the Mac's lowest-25%-height contact selection:

| Clip | Contact Z decrease | Z increase | Speed (source units/s) |
| --- | ---: | ---: | ---: |
| walk | .181449056 | 0 | .272173584 |
| run | .215487599 | 0 | .646462798 |
| carry | .181449056 | 0 | .272173584 |

`gait_direction_validation.json` preserves these measurements after deleting
the temporary probe. Walk speed varies .260864–.283452 across measured contact
intervals because waist roll/yaw and the retained planar IK affect the final
projection; the commanded stance path is linear. Run is .646437–.646484.
`gait_geometry_validation.json` records the root-basis proof and paw clearances.
Walk frames 1/7/17/27 each have three paws within .004 of the floor. Run frame
14 has all four paws .041688 above it. These floor-backed renders were inspected.
Walk/run/carry loop, floor, <20-degree frame-step, and fresh-import checks pass;
base and tier-2 authoring commands completed with renders enabled and both
verification commands exited zero. Export settings and geometry remain unchanged.

## Third tier: 10 storyboard petting/call clips

`tier3_clips.py` reuses the existing pose helpers and unmodified `Rig` pipeline.
`shiba_clips_tier3.blend` contains exactly these ten actions, active on
`shiba_pet_head_loop`. All actions have 28 sampled channels at 30 fps, exact
frame counts, and unchanged source geometry, weights, UVs, materials and rig.
The contract Clip list now has 34 entries (plus the separate Step-0 test asset).

| Clip | Frames | Loop | Motion / endpoint | Maximum seam angle |
| --- | ---: | --- | --- | ---: |
| `shiba_pet_head_loop` | 60 | yes | Upward head lean/tilt, folded ears, relaxed jaw | 0° |
| `shiba_pet_settle` | 90 | no | Idle → sit → held 75° root-roll side pose | 0° |
| `shiba_lie_side_loop` | 120 | yes | Side hold, ear flick, six-frame hind-paw twitch, tail tip | 0° |
| `shiba_belly_loop` | 90 | yes | 170° roll, supported back-arching pose, alternating forepaw curl | 0° |
| `shiba_lie_side_up` | 45 | no | Side first frame → head lift → sit_idle first frame | 0° |
| `shiba_call_stun` | 15 | no | Idle → ears snap forward in first three frames → freeze | 0° |
| `shiba_call_curious` | 40 | no | Held stun → yaw/tilt and asymmetric ears → held stun | 0° |
| `shiba_paws_up_enter` | 30 | no | Held call → seated rear and raised camera-facing pads | 0° |
| `shiba_paws_up_loop` | 90 | yes | Alternating forward paw pushes, small head bob/rear wiggle | 0° |
| `shiba_paws_down` | 30 | no | Raised paws lower along clearance arc → sit_idle first frame | 0° |

All six protected joints (`tail1`, `neck`, hips, shoulders) remain unrotated;
the export limit stays strictly under 7°. All four loops close exactly. The
four accepted-state entry/exit checks and eight full-pose chain checks have
zero matrix error. The additional side/belly comparison checks all eight hind
leg local channels; error is below 0.0000004. Its excluded joints and reason
are recorded explicitly: root/support, forepaws and head are intentionally
different, and the remaining joints are outside that partial-pose comparison.

`tier3_validation.json` stores the manifest, native export settings, chain
results and protected-asset SHA-256 hashes. `tier3_roundtrip_validation.json`
independently reopens the blend and all ten DAEs, checks every frame for floor
penetration and discontinuities, repeats exported loop/state/chain comparisons,
and checks pad facing and forward displacement. The source rest mesh extends
approximately .001579 below world zero; all poses remain within the unchanged
-.003 floor tolerance. Maximum fresh-import error is under .000003 source units
and the maximum joint step is under 9 degrees (unchanged 20-degree ceiling).
Both pad normals face +Z throughout the paws loop (minimum dot product 1.0).

Four event-selected QA frames per clip were rendered and inspected, plus one
retained representative per new clip in `previews/`. `review_sheets.ps1` assembles
the existing QA frames for review without editing animation. Side/belly poses
do not penetrate the floor beyond the source-rest tolerance; support/readability
limitations are listed below. The paws-up front view clearly shows both pads.
Eyes, blink, tongue, breathing and mood-tail layers are deliberately absent:
the source open-eye texture remains visible in these authoring previews.

```powershell
& 'C:\Program Files\Blender Foundation\Blender 4.2\blender.exe' --background --factory-startup --python-exit-code 1 --python blender/author_clips.py -- --tier3
& 'C:\Program Files\Blender Foundation\Blender 4.2\blender.exe' --background --factory-startup --python-exit-code 1 --python blender/verify_clips.py -- --tier3
```

Both commands exit zero with authoring renders enabled. These are Blender-side
authoring results only; Mac playback acceptance remains pending.

## Open issues

- The specified 0.65 walk duty with quarter-cycle offsets produces three-paw
  support for 60% of the cycle and two-paw support for 40%, not three at every
  instant. The exact requested phase schedule is retained; the reviewed frames
  have three supporting paws.
- The specified run phases mathematically overlap in stance at .45–.50 and
  .95–1, rather than creating suspension themselves. Positive body bob is also
  applied to foot-target height, creating visible suspension without changing
  the supplied phase schedule. Actual ground-contact duty is therefore shorter
  than the nominal .55 path duty.
- Forepaws need an 11-degree toe-down baseline to reach the floor with the
  mandatory 4% IK bend reserve. The specified 15-degree landing and 20-degree
  toe-off ramps are added to that baseline. Those ramps unwind over the first
  12% of stance / 20% of swing, avoiding discontinuous boundary jumps.
- A pure half-frequency head yaw cannot repeat smoothly in a one-cycle walk
  asset. A periodic, envelope-shaped left/right drift reaching +/-2 degrees
  replaces it; the first/last pose is exact. Mood/gaze remain runtime-owned.
- The short-stride values supplied here measure slower than the storyboard's
  illustrative 0.7-body-heights/s figure. They are not silently multiplied;
  Mac GaitStride should use the measured contact speed.
- The literal side-pose numbers left the model propped on a lower paw, with the
  torso floating. The lower right knee/elbow now tuck using distal roll (70°
  before the 10% relaxation), waist roll is 2° rather than 20°, and the root's
  requested lowering is -1.15 before the unchanged floor correction. The 75°
  root roll is preserved rather than relaxed. The held pose rests on the lower
  shoulder/thigh; the belly side is about .12–.20 above the floor and the head
  remains lifted about .41. It is a supported side-rest gesture, **not verified
  head-on-floor sleep**. The untouched rigid shoulder/hip pieces prevent a flat
  splay with these exact posture constraints; no seam limit is exceeded.
- Belly-up keeps root roll 170° but adds -12° whole-root pitch, head pitch 80°,
  and distal tail pitches -35°/-20° so neither an ear nor the tail tip props up
  the body. Root lowering is -1.25 before floor correction. It reads as an
  arched belly presentation, not a perfectly flat-backed rest. Hind local
  channels remain identical to side frame 1, including their asymmetric tuck.
- The call chain explicitly requires stun-last = curious-first = enter-first,
  while also requiring curious-last = enter-first. Curious therefore returns
  its yaw/tilt and ear asymmetry to STUN by frame 39, holding frame 40.
- Exact .6/1.2-Hz pet head/ear oscillations cannot repeat in the supplied
  60-frame loop. Whole harmonics give approximately .508/1.017 Hz (jaw 1.525
  Hz). Belly curls use two cycles, .674 Hz instead of .8. The side loop's
  storyboard chest breathing is omitted because this task assigns breathing
  exclusively to the Mac runtime. Sit_idle/sleep breathing is unchanged.
- Forepaw pushes use opposing distal elbow/wrist rotations instead of bone
  translations: approximately .02 forward, with a small downward arc. Pad
  orientation is preserved. Pelvis lowering leads the sit blend during entry,
  and a distal clearance arc prevents a forepaw from lifting the whole dog
  via the floor guard during paws-down.
