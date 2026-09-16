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
└ waist
  ├ tail1 › tail2 › tail3
  ├ Lleg1 › Lleg2 › Lfoot1 › Lfoot2
  ├ Rleg1 › Rleg2 › Rfoot1 › Rfoot2
  └ spin › chest
    ├ Larm1 › Larm2 › Lhand1 › Lhand2
    ├ Rarm1 › Rarm2 › Rhand1 › Rhand2
    └ neck › head
      ├ Lear1
      ├ Rear1
      └ mouth
```

SceneKit matches animation channels to nodes by name. Rename a bone, the clip silently does nothing.

## Toolchain

- **Blender 4.2 LTS** on Windows. 5.x removed Collada import; 4.2 has both import and export. Keep 5.x for nothing here.
- Import: File → Import → Collada, defaults, `Fix Leaf Bones` **off**, `Auto Connect` **off** (both alter the rig).
- Do not apply transforms, decimate, re-UV, or re-parent. Mesh and skin weights stay as ripped; only the armature gets keyed.

## Step 0 — go/no-go (do this before authoring anything)

1. Import `Sib_b.dae`, confirm 28 bones, mesh deforms when a bone is rotated in Pose Mode.
2. Key a 30-frame tail wag on `tail1`, export as `mac/Assets/shiba/clips/shiba_test_tailwag.dae` per the export settings below.
3. Commit + push. Mac side loads it on the coat-B model and reports back in the commit that follows.

If step 1 fails (no armature, exploded weights), stop and report — the fallback is re-rigging, which changes this whole plan.

## Clip list (12)

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

Locomotion is in-place; the app moves `skl_root`'s parent. Non-loop clips end on a pose the next state can start from (sit ends in sit_idle's first frame, etc.).

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

- `ModelLoader.load` loads the base model; clips are loaded via `SCNSceneSource` and attached to the pet node as `SCNAnimationPlayer`s keyed by clip name.
- Loop flag from filename sets `repeatCount = .infinity`.
- `SCNView.isPlaying` flips on when a clip runs and off at idle-clip end-of-cycle boundaries only if no clip is queued (CPU budget: 0.0% idle).

## Reporting back

Each side leaves a one-line result in its commit message for anything that touches the contract: `clips: tailwag exports, 28 bones intact` / `mac: tailwag plays on coat-B, no re-skin`. Problems go in this file under a `## Open issues` heading, not in chat.
