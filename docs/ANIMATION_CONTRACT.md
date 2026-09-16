# Animation contract: Blender (Windows) ↔ SceneKit (Mac)

Two machines, one repo, one branch (`feat/desktop-recreation`). This file is the interface between them. Change it here first; both sides read it before starting.

## Ownership

| Path | Owner | Never touched by |
| --- | --- | --- |
| `blender/` — `.blend` files, import/export scripts | Windows / Codex | Mac session |
| `mac/Assets/shiba/clips/` — exported clips | Windows / Codex (writes), Mac (reads) | — |
| `mac/Sources/`, `mac/Package.swift`, `mac/scripts/` | Mac session | Windows session |
| `docs/ANIMATION_CONTRACT.md` | shared; edit via commit, say so in the message | — |

## Three things sync through GitHub, nothing else

| What | Repo | Sync |
| --- | --- | --- |
| Code, contract, Shiba rip, exported clips | `davedoodz/nintendogs` (private) | `git pull --rebase` / `git push` |
| Plans and notes | Obsidian vault as its own private GitHub repo | Obsidian **Git** community plugin, auto pull on open + auto commit/push every 10 min, both machines |
| Session captures | `davedoodz/DavidOS` | `davidos capture --sync` (Mac) |

No Drive, no iCloud for any of these. Plan-level decisions live in the vault (`projects/nintendogs-mac-pet-plan.md`); build-level decisions live here.

Commit small and often. `git pull --rebase` before each work block. Assets are 636 KB; no LFS.

Everything under `mac/Assets/shiba/` is a copyrighted Nintendogs rip (see README § provenance). The repo is **private** and must stay private. Do not redistribute.

## Source model

`mac/Assets/shiba/aSib_b.nsbmd/Sib_b.dae` — coat B, black-and-tan. Textures beside it: `Sib_b_all.png` (body), `Sib_b_hand.png` (paws), `eye_0.png`. Materials are re-assigned at load time by name (`eye`, `hand`, everything else → body), so Blender material names must keep those substrings.

Rig — 28 joints, keep these names and hierarchy exactly:

```
skl_root
├ waist
│ ├ tail1 › tail2 › tail3
│ ├ Lleg1 › Lleg2 › Lfoot1 › Lfoot2
│ └ Rleg1 › Rleg2 › Rfoot1 › Rfoot2
└ spin
  ├ Larm1 › Larm2 › Lhand1 › Lhand2
  ├ Rarm1 › Rarm2 › Rhand1 › Rhand2
  └ chest › neck › head
    ├ Lear1
    ├ Rear1
    └ mouth
```

SceneKit matches animation channels to nodes by name. Rename a bone, the clip silently does nothing.

**Rigid skinning.** Every vertex is bound to exactly one joint (DS rigs have no weight blending), so a joint that meets the body — `tail1`, `neck`, `Lleg1`/`Rleg1`, `Larm1`/`Rarm1` — opens a visible seam when rotated far from rest. Keep those under ~10° and put the range in the next joint down the chain (`tail2`/`tail3`, `head`, `*2`/`*foot`/`*hand`). The first tail-wag test rotated `tail1` ±20° on a pitch axis and opened the tail-root seam. The corrected export keeps `tail1` stationary and rotates `tail2` ±20° in horizontal yaw. Mac captures over white confirmed a continuous butt-to-tail silhouette at both sampled poses. Evidence: `docs/screens/native-tailwag-seam-fixed.png`.

## Toolchain

- **Blender 4.2 LTS** on Windows. 5.x removed Collada import; 4.2 has both import and export. Keep 5.x for nothing here.
- Import: File → Import → Collada, defaults, `Fix Leaf Bones` **off**, `Auto Connect` **off** (both alter the rig).
- Do not apply transforms, decimate, re-UV, or re-parent. Mesh and skin weights stay as ripped; only the armature gets keyed.

## Step 0 — go/no-go (do this before authoring anything)

1. Import `Sib_b.dae`, confirm 28 bones, mesh deforms when a bone is rotated in Pose Mode.
2. Key a 30-frame tail wag on `tail1`, export as `mac/Assets/shiba/clips/shiba_test_tailwag.dae` per the export settings below.
3. Commit + push. Mac side loads it on the coat-B model and reports back in the commit that follows.

If step 1 fails (no armature, exploded weights), stop and report — the fallback is re-rigging, which changes this whole plan.

**Result: GO (2026-09-16).** Blender 4.2.23 preserved all 28 bones, the hierarchy, weights, UVs and materials. The corrected 30-sample `tail2` matrices moved only tail vertices while `tail1` stayed stationary. The native Mac app transferred that channel by node name onto the original coat-B rig and the white-background captures show a continuous butt-to-tail silhouette at both sampled poses. Evidence: `blender/step0_validation.json` and `docs/screens/native-tailwag-seam-fixed.png`.

## Clip list (24)

| File | Loop | Notes |
| --- | --- | --- |
| `shiba_idle_loop.dae` | yes | breathing, ear flick; 90–120 frames |
| `shiba_sit.dae` | no | stand → sit, ends held |
| `shiba_sit_idle_loop.dae` | yes | seated breathing |
| `shiba_lie_down.dae` | no | sit → lie, ends held |
| `shiba_sleep_loop.dae` | yes | lying, slow breath |
| `shiba_eat_loop.dae` | yes | head down, jaw (`mouth`) chewing |
| `shiba_walk_loop.dae` | yes | in-place, root does not translate |
| `shiba_run_loop.dae` | yes | in-place |
| `shiba_bark.dae` | no | 2 barks, `mouth` keyed |
| `shiba_fetch_pickup.dae` | no | head dip, mouth close |
| `shiba_happy.dae` | no | tail wag + bounce, used on pet/return |
| `shiba_stretch.dae` | no | wake-up stretch |
| `shiba_stand_from_sit.dae` | no | sit_idle → idle first frame; 45 frames |
| `shiba_sit_from_lie.dae` | no | sleep/lie → sit_idle first frame; 60 frames |
| `shiba_wake.dae` | no | sleep → sit_idle; head lifts before rising, ear flick; 60 frames |
| `shiba_beg_loop.dae` | yes | hungry cue: seated, head tilted up, small head bob; 90 frames |
| `shiba_yawn.dae` | no | idle → wide jaw opening/head back → idle first frame; 60 frames |
| `shiba_scratch.dae` | no | seated hind-leg scratch gesture → sit_idle first frame; 75 frames; ear-contact limitation in `blender/CLIPS_RESULT.md` |
| `shiba_look_around_loop.dae` | yes | bored idle variant: head turns left/right with pauses; 150 frames |
| `shiba_drink_loop.dae` | yes | head down, six jaw-lapping cycles (faster than eat); 60 frames |
| `shiba_alert.dae` | no | ears up, quick head turn toward viewer → idle first frame; 30 frames |
| `shiba_pet_react.dae` | no | head tilt, ears back, distal horizontal tail wag → idle first frame; 75 frames |
| `shiba_shake.dae` | no | head/chest/waist alternate small yaw → idle first frame; 45 frames |
| `shiba_fetch_carry_loop.dae` | yes | accepted in-place walk cycle, head up, mouth closed; 40 frames |

Locomotion is in-place; the app moves `skl_root`'s parent. Non-loop clips end on a pose the next state can start from (sit ends in sit_idle's first frame, etc.).

The second tier (`stand_from_sit` through `fetch_carry_loop`) uses a stricter **under 7°** limit on `tail1`, `neck`, `Lleg1`/`Rleg1`, and `Larm1`/`Rarm1`. Its non-loop entry and final poses are checked against the accepted state clips' first frames. Rebuild with `blender/author_clips.py -- --tier2` and verify with `blender/verify_clips.py -- --tier2` in Blender 4.2 LTS. See `blender/tier2_validation.json` and `blender/tier2_roundtrip_validation.json`; these authoring checks do not replace Mac playback review.

## Export settings (Blender 4.2 Collada)

- Selection only: armature + mesh
- **Include Animations: on**, `Keyframes` → *Sampled*, sampling rate 1, `Keep Keyframes` off
- Transform type: *Matrix*
- Global orientation: Y up, −Z forward (matches the source DAE; loader also sets `convertToYUp`)
- Apply modifiers: off; Triangulate: off
- Units: leave scale 1.0
- One action per file; frame range = the action's range; 30 fps

Filename is the contract: `shiba_<name>[_loop].dae`. Mac side derives the state machine from these names.

## Mac side (this is what consumes the files)

- `ModelLoader.load` loads the base model; `AnimationController` preloads all 24 exported scenes, validates every channel against the rig before mutation, and reuses same-named SceneKit animation players.
- `AnimationController.play(_:careRequest:restart:)` routes posture transitions with 0.25 s fades. Heartbeat requests are idempotent; explicit user actions use `restart: true`. `AmbientDirector` selects posture-safe flourishes and sequences without changing needs. `playClip(named:)` remains a diagnostic preview.
- `SCNView.isPlaying` and continuous rendering run only while motion is visible. The app owns a 100 ms foreground clock; sleep/hidden gaps do not advance it. The baseline `shiba_idle_loop` freezes on a rendered pose so the collapsed-tray process returns to 0.0% CPU. Fetch, wander, gaze and reactions reactivate the renderer. The Retina backing scale supplies edge smoothing; MSAA is disabled to keep the live app below its 120 MB RSS gate.
- The imported rig faces **+Z**, as established from head/mouth world positions. Walk, run and fetch-carry clips are in place. `SceneHost` applies their root translation and heading to `petAnchor`: ambient gait speed comes from the planted paw, while `FetchSequence` owns deterministic turn/run/pickup/carry/drop/celebrate phases.
- **Gait clips must move the planted paw toward −Z during contact** (head-first). `GaitStride` rejects a clip whose contact-phase paw motion is mostly +Z. The 2026-09-16 exports of `walk_loop`, `run_loop` and `fetch_carry_loop` were tail-first (`author_clips.py` had `target.z += stride·cos(phase)`), which the app rendered as a near-stationary moonwalk. The Mac side reversed those three clips' sample order in place and flipped the sign in `author_clips.py`. The next Windows rebuild of those clips supersedes the reversed files.
- Hand-keyed clips (call sequence, petting, overlays) follow `docs/BLENDER_HAND_ANIMATION.md` and export through `blender/manual_clips.py`, which applies the same sampling, basis conversion and seam-joint limits as the procedural clips. `shiba_layer_*` clips export only their keyed bones; Mac-side layered playback for them is pending.
- During fetch, the tennis ball is parented at the animated `mouth` joint. The Mac consumer reapplies the reciprocal inherited bone scale each tick; a raw child transform inherits Collada scale and makes the ball grow during the pickup-to-carry blend.
- Gaze is a constrained world-space rotation on `head`, preserving the joint's position and authored pose. SceneKit evaluates the transform constraint on its render queue, so cursor angles cross through a lock-protected sendable snapshot rather than a main-actor closure. `neck` and body-adjacent joints are not procedurally rotated. Begging and scratching are seated; yawning is standing; stretching is lying-to-standing.

## Reporting back

Each side leaves a one-line result in its commit message for anything that touches the contract: `clips: tailwag exports, 28 bones intact` / `mac: tailwag plays on coat-B, no re-skin`. Problems go in this file under a `## Open issues` heading, not in chat.
