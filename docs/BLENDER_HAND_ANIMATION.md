# Hand-animating the Shiba in Blender

For David, on the Windows PC with Blender 4.2 LTS. No rigging is needed: the rig exists, the export is scripted, and the checks run for you. You only pose bones and press **I**.

Read `docs/ANIMATION_CONTRACT.md` once. This page repeats the rules that matter while posing.

## 1. What you are working with

- One armature, 28 bones, already skinned. Never edit the mesh, weights, or bone hierarchy.
- The dog faces **+Z**. Its tail is at −Z.
- Every vertex belongs to exactly one bone (DS-era rigid skinning). Bending a bone where it meets the body opens a visible seam. The export refuses a clip if any of these six bones rotates more than **10°**: `tail1`, `neck`, `Lleg1`, `Rleg1`, `Larm1`, `Rarm1`. Put the motion in the next bone down the chain instead.

| Want to move… | Rotate this | Leave this nearly still |
| --- | --- | --- |
| Head (nod, turn, tilt) | `head` | `neck` (≤10°) |
| Ears | `Lear1`, `Rear1` | — |
| Jaw open/close | `mouth` | — |
| Tail wag | `tail2`, `tail3` | `tail1` |
| Front leg | `Larm2` (elbow), `Lhand1` (wrist), `Lhand2` (paw) | `Larm1` (shoulder ≤10°) |
| Hind leg | `Lleg2` (knee), `Lfoot1` (hock), `Lfoot2` (paw) | `Lleg1` (hip ≤10°) |
| Whole body lower/raise (sit, lie) | move `skl_root` (G key) and rotate it | — |
| Torso lean/roll | `spin`, `chest`, `waist` — a few degrees only | — |

- There is **no eyelid bone and no tongue**. Closed eyes will be a texture swap on the Mac side (see §7). Do not try to close the eyes with bones.
- Walk/run clips never move `skl_root`. All other clips may move it (sit lowers it, lie lowers it more).

## 2. One-time setup

From the repository root in PowerShell:

```powershell
git pull --rebase
& 'C:\Program Files\Blender Foundation\Blender 4.2\blender.exe' --background --factory-startup --python-exit-code 1 --python blender/manual_clips.py -- --setup
```

This writes `blender/shiba_manual.blend` with the coat-B dog, 30 fps, in Pose Mode. Open that file in the Blender GUI.

Optional, recommended: bring in the existing clips so you can copy their start/end poses. File → Append → `blender/shiba_clips.blend` → Action → pick e.g. `shiba_sit_idle_loop`. Then **rename the appended action to start with `ref_`** (e.g. `ref_shiba_sit_idle_loop`). The exporter only exports actions named `shiba_*`, so `ref_` actions are safe scratch material. Same for `shiba_clips_tier2.blend`.

## 3. Blender in ten lines (all you need)

1. Click the dog, press **Ctrl+Tab** → Pose Mode. Bones draw in front of the mesh.
2. Open a **Dope Sheet** editor, set its mode to **Action Editor** (dropdown in its header).
3. **New** action, name it exactly like the clip you are making (e.g. `shiba_call_stun`). Click the **shield icon** next to the name so the action is kept when you save. Without the shield, Blender discards it.
4. Set frame range in the Timeline: Start 1, End = the clip's frame count.
5. Frame 1: select all bones (**A**), press **I**. That keys the rest pose. Every clip starts this way unless it starts from another clip's pose (§5).
6. Move the playhead to the next key pose (every 8–15 frames is plenty). Click a bone, **R** then **X**, **Y** or **Z** (press the axis key **twice** for the bone's own axis), drag, click. Type a number for exact degrees (`R X X 15 Enter`). Wrong axis? **Ctrl+Z**, try another.
7. When the pose looks right, **A** then **I** again. Keying all bones every time keeps things simple and avoids bones "drifting" from unkeyed frames.
8. For a **loop**: at frame 1 select all bones, **Ctrl+C**. Go to the last frame, **Ctrl+V**, **I**. First and last pose now match; the exporter checks this.
9. Scrub or press **Space** to play. Blender interpolates between your keys; the exporter samples every frame.
10. **Ctrl+S**. Then export (§6).

Keep it small. Nintendogs motion is tiny: a head tilt is 10–15°, an ear flick 10°, a breath is 1° on `chest`. Big rotations look wrong on this mesh.

## 4. Clips to make, in order

Frame counts are at 30 fps. "Ends held" means the last pose is a still the app can hold. Names are the contract; the Mac side routes by name.

### A. The call (whistle) — start here

The sequence in the game: dog is off doing its own thing → hears you → freezes → looks over, curious → runs to the screen → stands up with both front paws on the glass. The run is already handled (`shiba_run_loop` plus root travel on the Mac). You author the three poses around it.

| Clip | Frames | Loop | What happens |
| --- | --- | --- | --- |
| `shiba_call_stun` | 20 | no | Standing. Freeze mid-motion: ears snap up and forward (`Lear1`/`Rear1` ≈ −12° pitch), head lifts 5°, tail stops. Ends held. Start from `ref_shiba_idle_loop` frame 1. |
| `shiba_call_curious` | 40 | no | From the stun pose: head turns toward the camera (`head` yaw ≈ 25°) with a tilt (`head` roll ≈ 15°), one ear rotates forward, other stays. Hold 10 frames. End facing the camera, head level again, ears up. Ends held. |
| `shiba_paws_up_enter` | 30 | no | Standing → rear drops into a sit (copy `ref_shiba_sit` last frame for the hindquarters and root), front paws lift and press forward at chest height, elbows bent, paws flat toward the camera (screenshots 12–13). Head looks up. Ends held. |
| `shiba_paws_up_loop` | 90 | yes | The held paws-up pose with life: paws alternately push 1–2 cm, head bobs, mouth (`mouth`) opens slightly twice, tail (`tail2`/`tail3`) wags. |
| `shiba_paws_down` | 30 | no | Paws lower back to the floor, body settles into `ref_shiba_sit_idle_loop` frame 1 exactly (copy that pose onto the last frame). |

### B. Petting

Petting the head in the game: eyes close, mouth opens in a smile, head pushes up into the hand (screenshot 3). Keep petting and the dog sits, then flops onto its side (4 → 6), then rolls onto its back for a belly rub with a wide happy mouth (7–9).

| Clip | Frames | Loop | What happens |
| --- | --- | --- | --- |
| `shiba_pet_head_loop` | 60 | yes | Standing. Head pushes up 8° and back, ears fold back 15°, `mouth` opens 10° and stays, tail wags. Slow, contented. |
| `shiba_pet_settle` | 90 | no | Standing → sit (reuse `ref_shiba_sit`) → tips over onto its left side: `skl_root` rolls ≈ 80° about Z and drops; legs relax outward; head rests. Ends held. |
| `shiba_lie_side_loop` | 120 | yes | On the side. Slow breathing (`chest` 1°), one ear flick, tail tip small wag, a hind paw twitch. |
| `shiba_belly_loop` | 90 | yes | Rolled onto the back (`skl_root` roll ≈ 170°), all four legs loose and slightly bent upward, `mouth` wide open 25°, head turned a little to the side. Gentle wriggle. |
| `shiba_lie_side_up` | 45 | no | From side → sit. End exactly on `ref_shiba_sit_idle_loop` frame 1. |

### C. Overlays (after the Mac side adds layered playback)

These key **only** the bones named; leave every other bone unkeyed. Name them `shiba_layer_*` and the exporter writes only the keyed bones so the app can play them on top of any body clip.

| Clip | Frames | Bones | What happens |
| --- | --- | --- | --- |
| `shiba_layer_tail_slow_loop` | 60 | `tail2`, `tail3` | ±15° yaw wag, one cycle. |
| `shiba_layer_tail_fast_loop` | 18 | `tail2`, `tail3` | ±20° yaw, one cycle — the "just got petted" wag. |
| `shiba_layer_pant_loop` | 30 | `mouth` | Opens 12°, closes, one cycle. |
| `shiba_layer_ear_flick` | 15 | `Lear1` | Quick −10° pitch and back. |

Do section A first. When `shiba_call_*` and `shiba_paws_up_*` land, the Mac side wires call → stun → curious → run → paws up.

## 5. Starting or ending on another clip's pose

Non-loop clips must begin on the pose the previous state ends on, and end on the pose the next state starts on, or the app fades through a visible pop. Use the `ref_` actions:

1. In the Action Editor switch to the `ref_` action, go to the frame you need (frame 1 for a loop; the last frame for a one-shot like `shiba_sit`).
2. **A**, **Ctrl+C**.
3. Switch back to your action, go to the target frame, **Ctrl+V**, **I**.

`shiba_sit_idle_loop` frame 1 is the seated handoff. `shiba_idle_loop` frame 1 is the standing handoff. `shiba_sleep_loop` frame 1 is the lying handoff.

## 6. Export, check, commit

```powershell
& 'C:\Program Files\Blender Foundation\Blender 4.2\blender.exe' --background --factory-startup --python-exit-code 1 --python blender/manual_clips.py
```

For one clip while iterating: append `-- --only shiba_call_stun`.

What it does for each `shiba_*` action: samples every frame, converts into the original DAE joint bases, writes `mac/Assets/shiba/clips/<name>.dae`, and fails loudly if:

- a seam bone exceeds 10° → the message lists the bone and its angle; move the rotation to the next bone.
- a `_loop` clip's first and last pose differ → copy frame 1 onto the last frame (§3 step 8).
- a bone other than `skl_root` was moved with **G** → only rotation is kept; the printed warning tells you which bone.

Results land in `blender/manual_validation.json`. Then:

```powershell
git add mac/Assets/shiba/clips blender/shiba_manual.blend blender/manual_validation.json
git commit -m "clips: call sequence (stun, curious, paws up), hand-keyed"
git push
```

Say which clips are new in the commit message. The Mac side pulls, loads them on the real model, and sends back captures for you to judge.

## 7. What the Mac side does after your clips arrive

Not your work; listed so you know it is covered.

- Route the new states: call → `shiba_call_stun` → `shiba_call_curious` → run toward the camera → `shiba_paws_up_enter` → loop → `shiba_paws_down`. Petting → `shiba_pet_head_loop`; sustained petting → `shiba_pet_settle` → `shiba_lie_side_loop` → stroke again → `shiba_belly_loop`.
- Closed eyes: a 32×32 `eye_closed.png` beside `eye_0.png` (paint a copy of `eye_0.png` with a dark curved line) swapped onto the eye material during pet/sleep/belly states. If you paint that texture, drop it in `mac/Assets/shiba/aSib_b.nsbmd/`.
- Layered playback for `shiba_layer_*` overlays so the tail, jaw and ears run independently of the body clip, with the fast wag triggered after petting.
- Tongue: the mesh has none. Out of scope unless we add a small textured quad later.

## 8. If something goes wrong

- Export says `assert bpy.app.version[:2] == (4, 2)`: you ran a different Blender. Use 4.2 LTS; 5.x cannot read the source Collada.
- Export says a bone is over the limit: reduce that bone, add the difference to its child (`neck` → `head`, `Larm1` → `Larm2`, and so on).
- Action vanished after reopening the file: the shield (fake user) was off. Redo it with the shield on.
- Dog looks fine in Blender but pops on the Mac: start/end pose does not match the handoff (§5).
- The dog will not lie flat / sinks through the floor: adjust `skl_root` location with **G**; the exporter does not auto-correct floor contact for hand-keyed clips.
