# Windows / Blender task prompt

Paste everything below the line into Codex Astra on the Windows machine. It is self-contained.

---

You are working in the private repo `davedoodz/nintendogs`, branch `feat/desktop-recreation`, on the **Windows** machine. You own `blender/` and `mac/Assets/shiba/clips/`. Do not touch `mac/Sources/`, `mac/Tests/`, `mac/scripts/` or anything under `docs/` except where this task says so — a Mac session is editing those concurrently and your commits must not conflict with it.

## Environment

- Blender **4.2 LTS** only: `C:\Program Files\Blender Foundation\Blender 4.2\blender.exe`. The pipeline asserts `bpy.app.version[:2] == (4, 2)`. Blender 5.x removed Collada import and cannot run this at all.
- Everything runs headless from the repo root. There is no GUI step and no hand-keying in this task.
- `git pull --rebase` before you start and again before each commit; the Mac side pushes to the same branch.

## Read first, in this order

1. `docs/ANIMATION_STORYBOARD.md` — the specification you are implementing. Sections 0, 2, 3, 5, 8, 10, 11 are yours.
2. `docs/ANIMATION_CONTRACT.md` — hard rules: joint names, rigid-skinning seam limits, export settings, ownership.
3. `blender/clip_pipeline.py` — the `Rig` class. Read `set_pose`, `action`, `export`. You will not need to change this file.
4. `blender/author_clips.py` — base-tier pose functions and `build()`. You change `gait()` and one assertion here.
5. `blender/tier2_clips.py` — second-tier pose functions, `SPECS`, and `build_tier2()`. Use it as the exact pattern for the new tier.
6. `blender/CLIPS_RESULT.md` — what was already validated and how results are reported.

## Conventions you must honour

- Pose functions return `{bone_name: (pitch, yaw, roll)}` in **degrees**, source-space, plus optional `"root_location": (x, y, z)`. `set_pose` converts them; parents carry descendants, so a child angle is relative to its parent.
- The rig faces **+Z**. `head` pitch + = nose **down**. `mouth` pitch + = jaw **open**. `Lear1`/`Rear1` pitch − = folded **back**. `tail2`/`tail3` pitch − = tail **raised**, yaw = wag.
- Rigid skinning: `tail1`, `neck`, `Lleg1`, `Rleg1`, `Larm1`, `Rarm1` must stay under the limit passed to `export` (10 for the base tier, 7 for tier 2 and the new tier). `export` asserts this and prints the offending joint. Move range to the next joint down the chain; never raise the limit.
- 30 fps, one action per DAE, sampled every frame, `t` normalized 0…1 across the clip.
- Never edit the mesh, weights, UVs, materials, bone hierarchy or object transforms. `export` re-checks the mesh signature and fails if anything changed.

## Task 1 — rewrite `gait()` in `blender/author_clips.py` (highest priority)

The current `gait()` produces a 50/50 sinusoidal swing/stance, which reads as a shuffle, and its stance phase is not a constant-speed backward slide, so the Mac's `GaitStride` measurement is unstable. Replace it per storyboard §2 (walk) and §3 (run). Keep the existing two-link IK solver and its bend reserve — only the foot *target path*, the phase schedule and the body motion change.

Note the sign convention that was already fixed on the Mac side: the planted paw must travel **−Z** during contact, i.e. `target.z -= stride * …`. The current file is already correct on this point; do not flip it back.

### Walk (`shiba_walk_loop`, 40 frames)

- Footfall phases (fraction of cycle), lateral sequence LH → LF → RH → RF:
  `Lleg` swing starts 0.00, `Larm` 0.25, `Rleg` 0.50, `Rarm` 0.75.
- **Duty factor 0.65**: for a limb with offset `o`, let `u = (t + 1 - o) mod 1`. Swing is `u < 0.35`, stance is `u >= 0.35`.
- Stance: paw z goes **linearly** from `+stride/2` to `−stride/2` across `u ∈ [0.35, 1.0]`; height 0.
- Swing: let `s = u / 0.35`. Paw z goes linearly from `−stride/2` to `+stride/2`; height `lift * sin(pi * s**0.8)` (peak near `s = 0.4`, so it lifts fast and lands soft).
- Stride: fore 0.17, hind 0.23. Lift: fore 0.10, hind 0.13.
- Paw pitch: last 20 % of swing rotate the toe joint (`*hand2`/`*foot2`) toe-down 15°, ramped; last 15 % of stance rotate +20° (toe-off). Apply on top of whatever the IK solver leaves on that joint.
- Hips/shoulders (`*leg1`/`*arm1`): ±4° in phase with the limb, forward at touchdown, back at toe-off. This is inside the 10° base-tier limit; keep it there.
- Body: `root_location.y` = +0.012 bumps at each fore touchdown (cycle phases 0.60 and 1.10 → 0.10), −0.008 at mid-stance. `waist` roll ±2° toward the hind leg in stance, `waist` yaw ±2° opposite the hind swing, `spin` pitch ±1° with the bob.
- Head: `neck` 0. `head` pitch +2° at each fore touchdown, yaw ±2° at half the cycle rate.
- Ears: +3° pricked, constant.
- Tail: `tail2` yaw ±5° at the cycle rate, phase-lagged 0.15 of a cycle behind `waist` yaw; `tail3` yaw ±3°, lagged a further 0.15. Carriage: `tail2` pitch −8, `tail3` −14 (the Mac layer will override carriage later; the clip still needs a sane sickle pose).
- Mouth closed.

### Run (`shiba_run_loop`, 28 frames)

- Diagonal pairs: `Larm` + `Rleg` swing 0.00–0.45; `Rarm` + `Lleg` swing 0.50–0.95. **Duty factor 0.55** (swing `u < 0.45`). Both diagonals are airborne around 0.45–0.50 and 0.95–1.00; that suspension is intentional.
- Stride: fore 0.24, hind 0.32. Lift: fore 0.16, hind 0.20.
- Body: `root_location.y` +0.04 at each suspension (phases 0.47, 0.97), −0.02 at mid-stance. `spin` pitch −3° at suspension, +2° at mid-stance; `waist` counter-pitch at half that.
- Head: pitch −4° at suspension, +3° at landing. Ears −6° (back). Tail: `tail2` pitch −10, yaw ±8° at the cycle rate. Mouth 8° open.
- Hips/shoulders ±6°. This is near the limit — if `export` rejects it, reduce to the largest value that passes and record the number you used.

### Required assertion change

`build()` currently asserts gait clips have **zero** root translation:

```python
rest = samples["skl_root"][0].translation
assert max((m.translation - rest).length for m in samples["skl_root"]) < 1e-6
```

The new gait has a deliberate vertical bob. Change this to assert that horizontal translation is still zero (the app owns forward travel) while allowing the vertical component:

- assert `abs(dx) < 1e-6` and `abs(dz) < 1e-6` for every sample, where `dx`/`dz` are the components of `m.translation - rest` in the **source basis' horizontal plane**;
- assert the vertical range is within `0.06` so a runaway bob cannot pass;
- report both numbers in the clip report (`root_horizontal_max`, `root_vertical_range`) instead of the current `root_translation_range: 0`.

Determine which component is vertical from the rig, do not guess: `shiba_sit`'s `root_location` is `(0, -0.61, 0)` in pose-function space, and `set_pose` maps that through `rest["skl_root"]`. Verify with a printout on one frame before you rely on it.

Also: gait clips are still built with `floor_contact=False` (the bob would be cancelled otherwise). Leave that as is.

## Task 2 — new clip tier (`blender/tier3_clips.py`)

Create `blender/tier3_clips.py` modelled exactly on `tier2_clips.py`: a `SPECS` dict, one pose function per clip, and a `build_tier3(render=True)` that exports each clip, checks loop closure for loops and entry/exit handoffs against the named accepted clips, hashes the clips it must not modify, and writes `blender/tier3_validation.json`. Wire it into `author_clips.py`'s `__main__` as `--tier3`, alongside the existing `--tier2`. Use `joint_limit=7`.

Reuse `SIT`, `LIE`, `blend`, `add`, `ease`, `pulse`, `window` by importing them, as tier 2 does. Do not duplicate them.

Clips, with their frame counts and handoff states. Full per-joint detail is in storyboard §5 (petting) and §8 (call):

| Clip | Frames | Loop | Incoming state | Outgoing state |
| --- | ---: | --- | --- | --- |
| `shiba_pet_head_loop` | 60 | yes | — | — |
| `shiba_pet_settle` | 90 | no | `shiba_idle_loop` | — (ends held on its own lying-on-side pose) |
| `shiba_lie_side_loop` | 120 | yes | — | — |
| `shiba_belly_loop` | 90 | yes | — | — |
| `shiba_lie_side_up` | 45 | no | — (starts from `shiba_lie_side_loop` frame 1) | `shiba_sit_idle_loop` |
| `shiba_call_stun` | 15 | no | `shiba_idle_loop` | — (ends held) |
| `shiba_call_curious` | 40 | no | — (starts on `shiba_call_stun`'s final pose) | — (ends held) |
| `shiba_paws_up_enter` | 30 | no | — (starts on `shiba_call_curious`'s final pose) | — (ends held) |
| `shiba_paws_up_loop` | 90 | yes | — | — |
| `shiba_paws_down` | 30 | no | — | `shiba_sit_idle_loop` |

Chain requirements beyond `SPECS`' existing incoming/outgoing check, which only compares against *accepted* clips on disk:

- `call_stun` final pose == `call_curious` first pose == (`paws_up_enter` first pose), and `paws_up_enter` final == `paws_up_loop` first == `paws_up_loop` last == `paws_down` first. Assert these across the in-memory samples with `matrix_error < 1e-3` and record them in the validation JSON as a `chains` list.
- `pet_settle` final == `lie_side_loop` first; `lie_side_loop` first == `lie_side_up` first; `belly_loop` first should match `lie_side_loop` first on the hind legs only (the roll differs) — assert the joints you can, and record which joints you excluded and why.

Authoring notes that will otherwise bite you:

- **Lying on the side and belly-up** need a large root roll (75° side, 170° belly). `set_pose` only reads `root_location` for translation; rotation of the whole dog goes through the `skl_root` **bone** angles in the returned pose dict. Put the roll on `skl_root`'s roll component and lower `root_location.y`. Check the mesh does not sink below the floor: these clips must use `floor_contact=True`, like every non-gait clip.
- The 7° seam limit applies to `Lleg1`/`Rleg1`/`Larm1`/`Rarm1`, so a "legs splayed out sideways" pose must come from `*leg2`/`*foot1`/`*arm2`/`*hand1`, not the hips and shoulders. If a pose is physically impossible within the limit, get as close as the limit allows, keep it, and write the limitation into `blender/CLIPS_RESULT.md` the way the existing scratch-reach limitation is documented. Do not break the limit and do not silently ship a broken-looking pose.
- `shiba_paws_up_*`: the rear is the `SIT` pose; the forelegs lift with `Larm2`/`Rarm2` ≈ −70°, `Lhand1`/`Rhand1` ≈ +40°, paws flat toward the camera. Sanity-check the paw pad orientation in a render.
- Eyes, tongue, blink, breathing and the mood-driven tail wag are **not** yours: they are Mac runtime layers. Author the clips' own tail/mouth/ear poses as specified and nothing more.

## Task 3 — thin the idle clip's breathing

Storyboard §6: the Mac runtime will own breathing as a layer, so `shiba_idle_loop`'s own chest breath would beat against it. In `idle()`, remove the `chest` breathing term and the `head` pitch breath, keeping the ear flicks and the small head yaw. Note this in the validation output. Do not touch `sit_idle`/`sleep` breathing yet — those states are not layered in this pass.

## Run and verify

```powershell
cd <repo root>
git pull --rebase
& 'C:\Program Files\Blender Foundation\Blender 4.2\blender.exe' --background --factory-startup --python-exit-code 1 --python blender/author_clips.py
& 'C:\Program Files\Blender Foundation\Blender 4.2\blender.exe' --background --factory-startup --python-exit-code 1 --python blender/verify_clips.py
& 'C:\Program Files\Blender Foundation\Blender 4.2\blender.exe' --background --factory-startup --python-exit-code 1 --python blender/author_clips.py -- --tier3
& 'C:\Program Files\Blender Foundation\Blender 4.2\blender.exe' --background --factory-startup --python-exit-code 1 --python blender/verify_clips.py -- --tier3
```

Add `--tier3` support to `verify_clips.py` the same way `--tier2` works. Append `--no-render` while iterating; do a final run **with** renders.

All four commands must exit 0. Do not weaken an assertion to make one pass; if an assertion fires, the pose is wrong.

### Gait direction check (do this, it caught a real bug)

The previous export had the planted paw moving the wrong way and it was only caught on the Mac. Before committing, prove the direction locally. Write a small throwaway script that, for `shiba_walk_loop`, `shiba_run_loop` and `shiba_fetch_carry_loop`, reads the exported DAE, composes `skl_root → waist → Lleg1 → Lleg2 → Lfoot1 → Lfoot2` per frame, and reports, for frames where the paw is in the lowest 25 % of its height range, the total z decrease versus the total z increase. **Decrease must dominate** (it is a head-first gait). Also report the contact-phase speed. Paste those numbers into the commit message. Delete the throwaway script afterwards.

Cross-check: the Mac's `GaitStride` uses exactly this measurement and rejects a clip whose contact-phase motion is mostly +Z, so a wrong-direction clip will fail to load in the app.

Note: the three gait clips currently in the repo were repaired on the Mac by reversing their sample order in place. Your rebuild supersedes them — that is expected and wanted.

### Rendered review

For each new or changed clip, render 3–4 frames into `blender/qa_frames/` (already gitignored) and **look at them**. Specifically confirm: the walk has three paws on the floor at the sampled frames, the run's suspension frame has all four off, the side-lying pose is not intersecting the floor, and the paws-up pose shows pads toward the camera. Keep one representative frame per new clip in `blender/previews/` and commit those.

## Report back

- Update `blender/CLIPS_RESULT.md` with a tier-3 section in the same style as the tier-2 section: table of clips, frame counts, motion summary, measured maximum seam-joint angle, loop/handoff results, and any limitation you hit (e.g. a pose the 7° limit prevents).
- Add a line to `docs/ANIMATION_CONTRACT.md`'s clip list for each new clip, and extend the clip-count wording. That file is shared — pull immediately before, and say in the commit message that you touched it.
- Do **not** edit `docs/ANIMATION_STORYBOARD.md`, `docs/ALIVENESS_PLAN.md`, or anything in `mac/Sources`. If the storyboard is wrong or impossible, implement the closest correct thing and write the discrepancy into `CLIPS_RESULT.md` under `## Open issues`.

## Commit and push

Small commits, one per task. Include the measured evidence in the message, e.g.:

```
clips: rebuild walk/run with real duty factors

Walk 4-beat lateral LH LF RH RF, duty 0.65, linear stance slide.
Run diagonal pairs, duty 0.55, suspension at 0.47/0.97.
Planted-paw contact z: walk -0.46 vs +0.00, run -0.61 vs +0.00 (head-first).
Contact speed walk 0.69, run 1.31 source-units/s.
Seam-joint max 6.2 deg (Rarm1). Root horizontal 0.0, vertical range 0.021.
```

Then `git push`. The Mac side pulls, loads the clips on the real model, and returns captures. Blender-side checks are authoring checks only — they do not constitute Mac acceptance, so do not claim the animation is accepted or shipped.

## Definition of done

1. All four Blender commands exit 0 with renders enabled.
2. Planted-paw z decrease dominates for all three gait clips; numbers in the commit message.
3. Ten new tier-3 clips exist in `mac/Assets/shiba/clips/`, all loops close, all handoff and chain assertions pass, `blender/tier3_validation.json` written.
4. `shiba_idle_loop` no longer contains its own chest/head breathing.
5. `blender/CLIPS_RESULT.md` and the contract's clip list updated; limitations documented rather than hidden.
6. Everything committed and pushed to `feat/desktop-recreation`; `git status` clean apart from ignored artifacts.
