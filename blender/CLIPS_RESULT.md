# Twelve clips: Blender authoring and roundtrip checks passed

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
| `shiba_walk_loop` | 40 | Four-phase foot cycle, in place, fixed root |
| `shiba_run_loop` | 28 | Faster diagonal pairs, larger steps, fixed root |
| `shiba_bark` | 60 | Two jaw openings with head/ear recoil; neutral ending |
| `shiba_fetch_pickup` | 75 | Head dip, jaw opens then closes, head returns |
| `shiba_happy` | 75 | Horizontal distal tail wag, two small bounces |
| `shiba_stretch` | 105 | Lying to foreleg extension to standing; held ending |

## Rigid-skinning constraints

`tail1` is stationary throughout all 12 clips. The six body-adjacent joints
stay at or below 7 degrees; their rotations are checked on every frame. The
larger movements use `tail2`/`tail3`, `head`, knees, elbows, hocks and paws.
Root motion for sit/lie/stretch moves the whole dog, preserving the torso joins.
Walk and run do not translate or rotate the root. Their two-link foot solver
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
