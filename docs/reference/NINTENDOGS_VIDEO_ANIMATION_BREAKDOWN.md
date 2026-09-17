# Nintendogs: video-to-Blender animation reference

Reference: [Nintendogs Lab & Friends | Nintendo DS | 4K 60fps | Part 1 — Octetra](https://www.youtube.com/watch?v=hb5j2v10eYs). Research date: 2026-09-16.

**Purpose:** reconstruct the visible dog performances, their timing, and their interaction context on the project's Collada skeleton. This is an evidence supplement to [ANIMATION_STORYBOARD.md](../ANIMATION_STORYBOARD.md), not a replacement export contract. Keep [ANIMATION_CONTRACT.md](../ANIMATION_CONTRACT.md) authoritative for assets, names, and delivery.

**Main conclusion:** the performance depends on attention changes, planted support, asymmetric adjustments, and expression changes at posture boundaries. A continuous wag, sinusoidal limb rotation, or a generic “happy” loop cannot reproduce it. Reconstruct the action sequence first, then its face and secondary motion.

## 0. Evidence, scope, and conventions

### What was actually examined

- Full recording coverage through **485 overview samples**, approximately one every two seconds, from 00:01 to 16:09.
- Seventeen overview contact sheets, independently inspected during synthesis. These locate events but cannot resolve fast motion or prove an event absent between samples.
- Sixteen retained close-study sheets, each with 24 samples at 4, 6, 8, or 12 samples/second. These cover approach, attention, sitting, lying, rolling, food, water, locomotion, gift presentation, and outdoor investigation.
- The original `mac/Assets/shiba/aSib_b.nsbmd/Sib_b.dae`, parsed directly for joints, hierarchy, skin influences, material names, and rest matrices.
- Existing storyboard, contract, and `blender/clip_pipeline.py` coordinate/pose conventions.
- Scientific canine locomotion references and animal-welfare expression guidance, listed in §12.

The downloaded inspection stream is **1920 × 1080, 60000/1001 fps, 970.2693 seconds**, AV1, video-only. “4K 60fps” is the upload title, not the properties of this inspection copy. No audio was analyzed. Microphone icons and written instructions establish the visible voice-input context, not the exact spoken words or vocal onset.

This is a sampled visual reconstruction study, **not recovered original animation data**. Exact original keys, hidden feet, joint rotations, game state thresholds, and original interpolation curves cannot be recovered uniquely from this video. The supplied DAE contains a rig and skin, **no original animation channels**. Exact reproduction would also require original motion and material-animation assets or additional source evidence.

### Confidence labels

- **[V] Visual:** directly visible in the inspected footage. Timestamp ranges are navigation windows unless finer sampling is stated.
- **[R] Rig:** directly measured from the source asset, or explicitly identified as an existing project contract.
- **[I] Inference:** a plausible mechanical or behavioral explanation, not a recovered game rule.
- **[A] Authoring:** a proposed implementation or key layout. Tune against the reference. These are not original Nintendo values.
- **Unknown:** genuinely occluded, unsampled, or unavailable. Do not turn this into a confident keyframe or trigger claim.

The close sheets label approximate sample centers. A 4 Hz sheet bounds a transition to roughly a quarter-second interval, not a single source frame. Fine time estimates below are rounded accordingly. Quantize final keys only after a full-rate pass in Blender.

### Which dogs to copy

**[V] Huayra is a red Shiba Inu.** The breed menu at 02:07–02:29 and status screen around 06:29 identify her. She has upright triangular ears, a curled tail, cream underside, white lower legs, and a compact puppy body. The title describes the game edition, not the breed throughout the video.

The opening kennel also shows a cream, floppy-eared dog, a long-bodied red, floppy-eared dog, and a small pale, upright-eared dog. Later breed previews explicitly identify Labrador Retriever, Miniature Pinscher, Toy Poodle, Miniature Schnauzer, Pembroke Welsh Corgi, and Shiba Inu. Treat the opening unconfirmed breed identities cautiously. Their silhouettes and appendage dynamics are not interchangeable with the Shiba.

The project contract chooses **coat B, black-and-tan**. This differs from Huayra's red coat. Motion can use the existing rig, but color-exact reproduction needs the matching coat and eye surround. Do not change production coat selection silently.

### Existing coordinate language

Use the storyboard's `pitch, yaw, roll` in degrees and 30 fps authoring convention. `t` means normalized clip time, not a source timestamp.

- **[R] Source pose space:** +Y up, +Z toward the muzzle, +X toward the dog's named left limbs.
- Head pitch positive lowers the nose. Yaw positive turns toward the dog's left in this convention. Verify each imported control with a small pose before authoring.
- `root_location.y` controls height. Horizontal travel belongs to the runtime parent for existing in-place locomotion clips.
- Export's **−Z forward setting is a coordinate-conversion setting**, not evidence that the source dog faces −Z.
- Left/right always means **the dog's** left/right. Use screen-left/right explicitly when describing an image. Never infer anatomical side from a front-facing screen direction alone.
- A pose bone's local Euler axis is not automatically the semantic pitch axis. The pipeline conjugates source-space rotations through the rest basis. Use that convention or a tested control rig.

## 1. Timestamped sequence inventory

Each interval below points to the video, not to an existing Blender action. Intervals include holds, transitions, or menus where stated. They are not proposed loop durations.

| Video window | Visible performance and context [V] | Reconstruction use |
| --- | --- | --- |
| [00:00–00:31](https://www.youtube.com/watch?v=hb5j2v10eYs&t=0s) | Splash, kennel entry, explanatory UI | No dog performance to reconstruct |
| [00:33–00:51](https://www.youtube.com/watch?v=hb5j2v10eYs&t=33s) | Several kennel dogs wander, approach the near boundary, turn, and briefly raise their forequarters | Multi-dog idle, approach, short rear, body-specific ear/tail treatment |
| [00:53–01:05](https://www.youtube.com/watch?v=hb5j2v10eYs&t=53s) | Close interaction with the red floppy-eared dog. Hand cursor over head, lowered/softened face, head movements | Petting on a different body type. Do not copy its ear silhouette onto Shiba |
| [01:07–01:21](https://www.youtube.com/watch?v=hb5j2v10eYs&t=67s) | Dog moves away and back among other dogs. Exit dialogue follows | Approach/disengage, near-boundary presentation, social spacing |
| [01:23–02:07](https://www.youtube.com/watch?v=hb5j2v10eYs&t=83s) | Breed-menu changes with three preview dogs moving in the yard | Shared action families with breed-specific proportions, not one universal tail motion |
| [02:09–02:33](https://www.youtube.com/watch?v=hb5j2v10eYs&t=129s) | Shiba previews: standing, sitting, low chest-down pose, head-up/open-mouth beats, turns, overlapping dogs | Shiba posture silhouettes. Occlusion prevents a clean full footfall chart |
| [02:37–02:51](https://www.youtube.com/watch?v=hb5j2v10eYs&t=157s) | New puppy walks around the room. Tutorial describes unfamiliarity and asks for interaction | Arrival wander. “Nervous” is the game's text, not a diagnosis from a curled tail |
| [02:53–02:59](https://www.youtube.com/watch?v=hb5j2v10eYs&t=173s) | Puppy notices the viewer, approaches, then turns away as dialogue continues | Notice → orient → approach. Do not require a paws-up finish |
| [03:03–03:08](https://www.youtube.com/watch?v=hb5j2v10eYs&t=183s) | Whistle interaction/view change, frontal approach, near stop | Root travel and deceleration reference |
| [03:09–03:17](https://www.youtube.com/watch?v=hb5j2v10eYs&t=189s) | Hand strokes head. Eyes narrow/close, ears flatten outward/back, jaw opens. Dog becomes seated | Standing and seated pet response |
| [03:17–03:21](https://www.youtube.com/watch?v=hb5j2v10eYs&t=197s) | Seated dog tips onto side, then remains laterally supported during touch | Side-settle and side-pet loop |
| [03:21–03:23](https://www.youtube.com/watch?v=hb5j2v10eYs&t=201s) | Side-rest dog lifts head, rotates chest toward floor, arranges forepaws forward | **Side → chest-down**, not necessarily side → sit |
| [03:23–03:29](https://www.youtube.com/watch?v=hb5j2v10eYs&t=203s) | Chest-down petting, head/face response | Prone pet loop |
| [03:29–03:39](https://www.youtube.com/watch?v=hb5j2v10eYs&t=209s) | Returns to side. Touch continues on torso. Upper hind leg makes larger lifted beats | Side rub and leg response, not ordinary standing scratch |
| [03:39–03:43](https://www.youtube.com/watch?v=hb5j2v10eYs&t=219s) | Side-rest face opens/closes mouth and moves toward touch. Torso rolls farther belly-up near 03:42.7 | Belly exposure is a distinct transition, not a permanently supine idle |
| [03:43–03:46](https://www.youtube.com/watch?v=hb5j2v10eYs&t=223s) | View changes. Dog rolls chest-down, pushes up, turns, and departs | Recover → stand → locomotion. View wipe is not a skeletal transition |
| [03:49–04:01](https://www.youtube.com/watch?v=hb5j2v10eYs&t=229s) | Distant sit, another approach, renewed near petting | Repeatable engagement cycle |
| [04:05–04:23](https://www.youtube.com/watch?v=hb5j2v10eYs&t=245s) | Naming instructions. Dog remains active behind dialogue | Menu-visible ambient state, not necessarily frozen animation |
| [04:24–04:27](https://www.youtube.com/watch?v=hb5j2v10eYs&t=264s) | Microphone UI. Head turns first, body follows through short steps, dog faces viewer and holds | Listening orientation, measured close study |
| [04:29–05:55](https://www.youtube.com/watch?v=hb5j2v10eYs&t=269s) | Repeated input prompts, orientation, facing holds, head tilts/question-mark feedback, open-mouth response beats | Heard/uncertain/recognized outcomes. Do not invent a fixed response to every input |
| [05:55–06:23](https://www.youtube.com/watch?v=hb5j2v10eYs&t=355s) | Learned-name feedback, keyboard naming, standing dog with small head and mouth changes | Success feedback plus attentive idle |
| [06:25–06:43](https://www.youtube.com/watch?v=hb5j2v10eYs&t=385s) | Room movement, status check, sit, then approach into close interaction | State changes do not map one-to-one to dialogue pages |
| [06:45–06:49](https://www.youtube.com/watch?v=hb5j2v10eYs&t=405s) | Standing petting → sit around 06:48 | Clear asymmetric forepaw adjustment during lowering |
| [06:49–06:55](https://www.youtube.com/watch?v=hb5j2v10eYs&t=409s) | Seated petting, then forward/down transition | Sit → chest-down reference |
| [06:55–07:07](https://www.youtube.com/watch?v=hb5j2v10eYs&t=415s) | Chest-down petting, closed eyes, changing mouth, sparkle feedback | Prone relaxation, not a raised-rump play bow |
| [07:09–07:23](https://www.youtube.com/watch?v=hb5j2v10eYs&t=429s) | Dog leaves, reorients, approaches, and accepts head contact | Disengage/re-engage variants |
| [07:27–07:41](https://www.youtube.com/watch?v=hb5j2v10eYs&t=447s) | Tutorial explicitly instructs gentle head petting followed by a quick downward stylus slide. Dog sits | Gesture-driven sit, distinct from elapsed-petting inference |
| [07:43–08:41](https://www.youtube.com/watch?v=hb5j2v10eYs&t=463s) | Training-icon instructions, repeated sit demonstrations and audio association attempts | Learn command from a just-performed posture, then hold/release |
| [08:43–09:19](https://www.youtube.com/watch?v=hb5j2v10eYs&t=523s) | Trick named “Sit down.” Dog later approaches and sits during command test | Learned command → sit |
| [09:21–09:49](https://www.youtube.com/watch?v=hb5j2v10eYs&t=561s) | Tutorial wrap-up, supply menus, dog rolls on its back in background near 09:47 | Ambient roll can occur without active belly petting |
| [09:51–10:13](https://www.youtube.com/watch?v=hb5j2v10eYs&t=591s) | Bubble Blower selected. Dog orients, moves toward bubbles, changes direction, partially disappears behind wand/bubbles | Toy tracking and short pursuit. No verified tennis-ball fetch here |
| [10:17–10:25](https://www.youtube.com/watch?v=hb5j2v10eYs&t=617s) | Red Leather Collar equipped, then care supplies selected | Accessory change, not a new gait |
| [10:27–10:45](https://www.youtube.com/watch?v=hb5j2v10eYs&t=627s) | Water bowl, approach, muzzle lowering, repeated drinking posture, head lift/end | Drink. Status later reads thirst “Quenched,” hunger still “Hungry” |
| [10:55–11:19](https://www.youtube.com/watch?v=hb5j2v10eYs&t=655s) | Dry Food selected. Kibble bowl, curved approach, stable eating stance, head lift and sit | Eat, separate from drink |
| [11:21–11:41](https://www.youtube.com/watch?v=hb5j2v10eYs&t=681s) | Supplies navigation with standing/sitting background dog | Ambient movement while menus operate |
| [11:43–12:55](https://www.youtube.com/watch?v=hb5j2v10eYs&t=703s) | Dog Care Book pages: status, meals, shampoo, brushing, walking, saving | **Illustrations/instructions**, not a live bath/brush performance by Huayra |
| [12:57–13:29](https://www.youtube.com/watch?v=hb5j2v10eYs&t=777s) | Returns to live room, chooses Walk, draws and confirms route | Walk-mode entry and route planning |
| [13:31–14:03](https://www.youtube.com/watch?v=hb5j2v10eYs&t=811s) | Leashed side-view travel, glances toward viewer, short forequarter lift near 13:34, continuing gait | Best lateral locomotion reference, plus leash reaction |
| [14:04–14:15](https://www.youtube.com/watch?v=hb5j2v10eYs&t=844s) | Dog brings wrapped gift, approaches camera, raises both forepaws with pads toward viewer. Gift disappears with sparkle, mouth opens | Carry/present/reward/drop-down sequence. Gift contains Tennis Ball |
| [14:17–14:29](https://www.youtube.com/watch?v=hb5j2v10eYs&t=857s) | Resumes route, pauses in a lowered seated/squatting pose, then moves | Outdoor stop variant. Do not label the first hold's physiology from overview alone |
| [14:31–15:01](https://www.youtube.com/watch?v=hb5j2v10eYs&t=871s) | Locomotion, another pause, glances and turns | Repeated start/stop behavior, not one uninterrupted walk loop |
| [15:02–15:11](https://www.youtube.com/watch?v=hb5j2v10eYs&t=902s) | Nose lowers close to ground during small steps, body turns, compact squat, cleanup-bag graphic, rise | Ground investigation → elimination/cleanup context → recovery |
| [15:13–15:39](https://www.youtube.com/watch?v=hb5j2v10eYs&t=913s) | Route travel resumes. Dog leaves view, return-home message | End walk only after travel exits |
| [15:43–15:53](https://www.youtube.com/watch?v=hb5j2v10eYs&t=943s) | Home again. Distant stand → sit → chest-down before save screen | Post-walk settling. Not evidence of a sustained sleep cycle |
| [15:55–16:10](https://www.youtube.com/watch?v=hb5j2v10eYs&t=955s) | Saving UI and small loading icon | No further full dog performance |

## 2. Rig map: what the modeller can actually control

### 2.1 Measured source facts [R]

See [rig-facts.json](hb5j2v10eYs/rig-facts.json) for the independently parsed hierarchy and global rest positions.

- 28 joint nodes.
- 1,140 skin entries. Every vertex has one influence.
- No `<animation>` elements and no morph controllers in the original DAE.
- Material names: `Dg_eye`, `Sib_b_all`, `Sib_b_hand`.
- The asset element contains dates but no explicit unit or up-axis declaration. Do not claim a measured physical size in meters.
- Example global rest positions in source units: head `(0, 2.51544, 1.49505)`, mouth `(0, 2.26254, 1.90327)`, tail root `(0, 2.11588, -1.27999)`.
- Left forepaw joint `Lhand2` has X `+0.44995`. Right forepaw joint `Rhand2` has X `-0.44995`. This independently resolves the source facing/side convention.

```text
skl_root
├─ waist
│  ├─ tail1 → tail2 → tail3
│  ├─ Lleg1 → Lleg2 → Lfoot1 → Lfoot2
│  └─ Rleg1 → Rleg2 → Rfoot1 → Rfoot2
└─ spin
   ├─ Larm1 → Larm2 → Lhand1 → Lhand2
   ├─ Rarm1 → Rarm2 → Rhand1 → Rhand2
   └─ chest → neck → head
                         ├─ Lear1
                         ├─ Rear1
                         └─ mouth
```

| Visible function | Existing bones | Authoring instruction [A] |
| --- | --- | --- |
| Whole-body height, pitch, roll | `skl_root` | Move body around changing support. Compensate root translation when rolling so the body does not rotate through the floor |
| Pelvic lowering and hindquarter orientation | `waist`, both `*leg*`/`*foot*` chains | Fold the rear while tracking paw position. Do not scale the dog to make it sit |
| Thorax tilt and shoulder mass | `spin`, `chest` | Keep the chest distinct from the pelvis. Foreleg chains attach to `spin`, not `chest` |
| Head aim, tilt, pet lean | `head`, conservatively `neck` | Let `head` carry most expression. Protect the body-adjacent neck seam |
| Forelimb support/reach | `Larm1/2`, `Lhand1/2`, mirrored right | Treat these as a simplified shoulder/upper-limb, elbow-region, carpus/paw chain. Confirm actual bend locations visually |
| Hindlimb folding/kick | `Lleg1/2`, `Lfoot1/2`, mirrored right | Dog hock is an ankle, not a backward knee. Preserve digitigrade silhouette |
| Curled tail and wag | `tail1/2/3` | Preserve breed curl. Existing seam policy holds `tail1` near rest and puts oscillation in `tail2/3` |
| Ear silhouette | `Lear1`, `Rear1` | One joint per ear. Animate tilt/splay, not invented multi-segment floppy-ear bending |
| Jaw opening | `mouth` | Close for held objects, open for visible mouth beats. Check interior at extremes |
| Eyelids and eye shape | No eye/eyelid bones | Use material/texture states. The source eye material is separate |
| Tongue/lip/brow detail | No dedicated bones or morph controls | Existing runtime additions are not original DAE controls. Do not promise a skeletal-only match |

### 2.2 Preserve the asset contract

**[R, project rule]** Use Blender 4.2 LTS for this Collada pipeline. Keep bone names, hierarchy, mesh, weights, UVs, and material identity unchanged. Disable leaf-bone fixing and auto-connect. Do not apply generic pipeline advice to decimate, reweight, rename, re-parent, or apply arbitrary transforms.

The project documents seam risk at `tail1`, `neck`, `Larm1`, `Rarm1`, `Lleg1`, and `Rleg1`. Existing tiers use conservative limits of approximately 10° or stricter than 7°. These are **project deformation safeguards**, not anatomical limits, and not a theorem that every rigid-skinned dog tears above 7°.

Make the pose fit through distal articulation, root height, and body orientation. If those constraints prevent the reference silhouette, report the mismatch. Do not hide it by calling the restricted result exact. A different skin/rig would be a separately approved asset change.

### 2.3 Use temporary controls without changing the exported skeleton [A]

Create four non-deforming paw targets, fore/hind bend guides, a root control, and a head target in the authoring scene if needed. Keep them outside the exported deform hierarchy. Bake their solved motion onto the original named joints.

For each pose, record which paws are planted. A planted paw target stays fixed in world space while the body changes above it. Do not freeze all four targets while demanding a large turn or rear-up. Release the appropriate contact, reposition that paw, then plant it again.

The anatomical knee/elbow label is a guide, not permission to copy human IK settings. Derive the chain lengths and bend directions from the imported rest pose.

## 3. Locomotion: walk, approach, starts, stops, turns

### 3.1 What gives this puppy its movement [V]

The side-view route shows a compact body, short quick steps, a relatively stable back, an open mouth in many travel samples, and the curled tail above the rump. The head can turn toward the viewer without immediately turning the whole route. The leash changes shape with the collar and hand position.

The frontal approach at 03:06.2–03:07.9 alternates visible forelimb reach. The dog grows in screen size as it nears the viewer. Do not reproduce that solely by scaling the mesh. The camera also changes across the UI wipe, so do not measure a single continuous world trajectory through the wipe.

Evidence: [approach](hb5j2v10eYs/approach_184.jpg), [side travel and short rear](hb5j2v10eYs/gait_814.jpg), [steady side travel](hb5j2v10eYs/stride_819.jpg).

### 3.2 Contact-first construction [A]

1. Select a repeatable side-view stride inside 13:39–13:41. Separate the head glance from the limb cycle.
2. Mark each visible paw's touchdown, mid-stance, toe-off, passing pose, and forward reach.
3. Mark hidden far-side feet as inferred. Do not call them measured contacts.
4. Fit root speed from planted paw motion relative to the ground. Camera tracking makes screen-space root speed misleading.
5. Fit pelvis and chest motion after the foot paths work.
6. Add head compensation, jaw state, ears, and tail last.

**Stance:** in the existing in-place +Z-facing clip, a planted paw travels toward **−Z relative to the body**. The runtime's +Z travel cancels that movement. If `z_paw` is the body-relative paw coordinate, straight-line no-slip requires approximately `v_root = -dz_paw/dt` during contact.

**Swing:** lift the paw clear, flex the distal chain, pass beneath the body, then reach forward. Keep vertical velocity gentle at touchdown. A full sine wave is not a flat planted segment.

**Body:** let loaded limbs compress slightly at contact. Do not make the torso bounce merely because a sine timer says so. Head movement can partially oppose thorax movement to keep the gaze stable.

**Turns:** aim the head, take a short step, rotate the torso through support transfer, then align the hindquarters. The listening turn at 04:24 demonstrates this clearly. A planted four-paw dog rotating as one rigid turntable is wrong.

### 3.3 Gait classification and numerical guardrails

**[V]** The retained side samples show alternating limb configurations and brisk travel, but do not establish a complete four-foot contact chart. Do not label every travel passage “canter” or guarantee a flight phase from these samples.

**[A]** Reuse `shiba_walk_loop` for a four-beat reconstruction and `shiba_run_loop` only for a verified faster contact pattern. Names describe the current interface, not proof of the original gait.

- A lateral-sequence walk can be represented as LH → LF → RH → RF, with contralateral limbs half a cycle apart. Actual interlimb offsets need fitting.
- A trot uses diagonal pairs. A canter is asymmetric and is not merely a bouncy trot.
- A hypothetical pair schedule with diagonal pair A grounded for 55% of a cycle and pair B offset by 50% has **overlap, not flight**. This is a mathematical fact about that schedule.
- For a proposed aerial diagonal gait, choose actual non-overlapping contact windows. Do not add root bob to a contact schedule that still pins feet and claim suspension.
- Duty factor alone is not a sufficient universal classifier for every quadrupedal gait. Use footfall order, phase relationships, support, and body motion together.

The current storyboard's 40-frame walk and 28-frame run are **existing authoring choices**, not source measurements. At 30 fps, an inclusive frame range 1–40 spans 39 frame intervals between its first and last keys. State whether the exported loop includes a duplicate endpoint before comparing duration.

A practical first block can use the existing cycle lengths, but final timing must follow the selected footage. Preserve the faster cadence of short legs rather than stretching the stride until the puppy appears to glide.

### 3.4 Start, stop, and short forequarter lift

**[V]** Around 13:34.0–13:34.4 the dog has both forepaws raised, body tipped upward, then returns to four-foot travel. The dense sheet starts with the raised pose, so it does **not** capture the full anticipation or prove an airborne jump.

**[A]** Build this as a short rear/forequarter-lift variant: rear support → forelegs unload and fold → chest lifts → forepaws reach down → contact compression → travel. Do not use the long near-camera paws-up hold as the same action. The visible leash context supports a leash-related reaction, but the exact input cause is unknown.

For stopping, finish a useful support phase, shorten the final step, and settle the body. A generic crossfade can be the playback mechanism, but it does not guarantee invisible foot sliding. Inspect the actual blend.

## 4. Tail, ears, eyes, jaw, and attention

### 4.1 Tail: preserve the curl before adding wag

**[V]** Huayra's tail retains a curled or sickle silhouette through standing, walking, and many interactions. The projected silhouette changes with body heading. In the listening-turn sheet, a curl briefly looks much straighter from another angle. Do not interpret every silhouette change as a complete uncurl animation.

**[A]** Separate tail carriage from wag. Fit the resting curve first. Add a limited `tail2` yaw and smaller delayed `tail3` response only where the reference supports it. A small pelvis response can accompany vigorous movement, but never synchronize every body part to one oscillator.

Do not claim a measured 4 Hz wag, permanent rightward bias, hunger droop, or fixed alert freeze from this footage. These may be design choices, not observed rules. Scientific tail laterality findings do not establish that Nintendo implemented them.

### 4.2 Ears: silhouette matters more than large rotations

**[V]** During close petting, the pointed ears often flatten or splay. During sit/lie transitions they can return to a more upright/rounded frontal silhouette before softening again. A head turn also changes the apparent ear shape.

**[A]** Key each ear independently, with only small asymmetry unless clearly visible. Reserve asymmetry for head tilt, recovery, and direction changes. Avoid perfectly mirrored mechanical flapping. With one joint per ear, retain stiffness appropriate to a Shiba rather than simulating a Labrador's hanging pinna.

### 4.3 Face: treat combinations as states, not one “smile”

| Visible combination [V] | Best reference | Reproduction [A] |
| --- | --- | --- |
| Eyes closed/narrow, ears splayed, open jaw while hand touches head | 06:47, 06:49–06:54 | Pet face state, with small jaw changes and head response |
| Eyes reopen, mouth reduces, ears more upright during posture change | 06:48–06:49 and 06:54.8–06:55.6 | Temporarily restore attention during the transition |
| Closed eyes, repeated mouth changes while lying | 03:18–03:21, 06:56–07:01 | Side/prone pet state. Do not freeze the jaw for the whole hold |
| Open eyes and relatively closed mouth during microphone-facing hold | 04:25.5–04:26.9 | Attentive listening, not continuous panting |
| Gift obscures muzzle, eyes remain visible, forepaws raised | 14:05–14:07.4 | Carry face owns jaw. Suppress generic pant |
| Gift disappears, mouth opens wide, eyes soften/close briefly | Around 14:07.5 | Release/positive feedback beat, synchronized with object event |

The sampled evidence does not establish a universal “eyes close exactly 150 ms before mouth opens” rule. Preserve local ordering where visible, but do not apply one timing offset to every interaction.

A jaw opening without audio is not proof of a bark. Label bark-like visual beats separately from confirmed sound. Likewise, closed eyes during touch are not proof of sleep.

### 4.4 Listening and uncertainty

Close study: [04:24–04:27](hb5j2v10eYs/alert_264.jpg).

**[V] Approximate sequence:** side-facing at 04:24.1 → head turns toward viewer by about 04:24.4 → mouth closes and short repositioning steps follow → body nearly frontal by 04:25.4 → attentive hold through the end of the study.

**[A]** Fit the orienting segment to roughly one second as a starting layout. Put gaze acquisition before body alignment. Keep forepaw adjustments asymmetric and preserve the standing posture. The clip should return control to attention/idle if the input does not produce an approach.

During naming, question-mark UI accompanies head-tilt uncertainty in overview samples, notably around 05:01, 05:35, and 05:49. **[I]** This supports an uncertain recognition outcome. It does not prove which sound feature failed or how many attempts the original game requires.

Do not hardcode “every sound freezes the dog for 0.5 seconds.” The observed listening turn begins while the dog is already active.

## 5. Head petting and posture changes

### 5.1 Standing → seated petting

Primary sheet: [06:47–06:51](hb5j2v10eYs/sit_407.jpg).

**[V]** At 06:47 the dog stands with eyes closed, ears softened, and jaw open. Near 06:48 the face becomes attentive. The pelvis lowers, hind paws move into a wider seated arrangement, and the forepaws reposition rather than remaining perfectly symmetric. By approximately 06:48.9–06:49.1 the dog is seated. The softer pet face resumes.

**[A] Suggested 30 fps blocking, approximately 0.9–1.0 seconds:**

| Local key | Body/support | Head and face |
| --- | --- | --- |
| F1 | Match standing entry. All current contacts inherited | Match current pet state |
| F4–F8 | Shift body slightly back/down, begin rear folding | Open eyes enough for the attentive transition |
| F9–F18 | Lower pelvis. Reposition one forepaw while the other supports. Hind paws find seated support | Reduce jaw opening, keep muzzle toward interaction |
| F19–F27 | Complete seat, arrange both forepaws under chest, damp body motion | Restore relaxed expression after the body is stable |
| F28–F31 | Held seated entry for the loop | Small head response continues |

These frame numbers are blocking estimates derived from the observed interval, not original keys. The precise identity of a briefly occluded hind contact remains inferred.

Use `shiba_sit` → `shiba_sit_idle_loop` as the interface. The face layer must not overwrite the attentive transition with closed eyes throughout.

### 5.2 Gesture-driven sit is a separate trigger

Primary sheet: [07:40–07:43](hb5j2v10eYs/gesture_sit_460.jpg).

**[V]** The tutorial says to pet the top of the head and then quickly slide the stylus downward. A hand cursor appears, the dog lowers into a seat, and the training icon appears. The lowering occupies roughly 07:40.8–07:41.5 in the dense samples. The face is more focused during the movement and opens into a relaxed mouth afterward.

**[A]** Reuse the sit posture mechanics, but trigger them from a recognized downward head gesture. Do not wait for an arbitrary six-second petting timer when this gesture occurs. Once the dog is seated, the training system can associate the next input with the just-performed action.

### 5.3 Sit → chest-down

Primary sheet: [06:54–07:00](hb5j2v10eYs/down_414.jpg).

**[V]** The dog sits through about 06:54.6, begins moving forward/down around 06:54.8, and is chest-down by about 06:55.4–06:55.6. Forepaws reach forward as the thorax lowers. The head stays lifted above the floor. Hind feet remain visible to the sides. Petting expressions resume and sparkles appear.

**[A]** Start with seated support. Move forepaws forward, flex the forelimbs, lower chest and pelvis, then settle. Do not pitch the whole rigid dog forward while leaving straight forelegs. Keep the muzzle above the floor and maintain contact under the forepaws.

Suggested block: 20–26 frames at 30 fps, with the paw reach leading the final chest settling. Use `shiba_lie_down` if its entry is seated. End on a **prone-awake** hold, not automatically on a sleeping face.

This is not a play bow: the rear is also low. A play bow would leave the hindquarters clearly raised.

### 5.4 Seated → side rest

Primary sheet: [03:17–03:23](hb5j2v10eYs/roll_197.jpg).

**[V]** At 03:17.1 the dog is seated. It lowers and tips laterally, arranges its forelegs, and lies on its side by roughly 03:18.1–03:18.4. The head settles last. The face then closes/softens while touch continues. One upper hind leg extends upward more strongly near 03:21.1.

**[A] Suggested phase proportions:**

- 0–20%: seated anticipation and lateral weight transfer.
- 20–60%: lower shoulder/hip toward the supporting side. Fold the lower limbs to avoid floor penetration.
- 60–85%: settle the lateral torso, then head. Keep the upper paws loose rather than symmetrically pinned.
- 85–100%: damp rotation and enter side-rest breathing/head response.

Fit approximately 1.0–1.3 seconds initially. Roll the root while translating it to preserve a plausible floor contact pivot. Do not rotate 75° around the root's original standing height.

The existing `shiba_pet_settle` includes standing → sit → side. For close matching, do not replay its standing entry when the dog is already seated. Author or select the correct entry segment.

### 5.5 Side rest → chest-down, not a mandatory sit

In the same sheet, around 03:21.3–03:22.4, the dog lifts its head, brings the thorax over its forepaws, and finishes chest-down with the forelegs forward.

**[A]** Sequence: head lift → forepaw placement → roll chest under → recover pelvic alignment → prone hold. Rotate around the supported side and the newly planted paws. Do not force a high seated torso halfway through unless the source shows it.

The current `shiba_lie_side_up` contract ends seated. It therefore does **not** exactly reproduce this event. A proposed `shiba_side_to_prone` action would fill the gap. That name is a recommendation only, not an existing required file.

### 5.6 Side petting, leg response, and belly roll

Primary sheet: [03:39–03:45](hb5j2v10eYs/belly_219.jpg), with overview context 03:29–03:43.

**[V]** The side-rest dog moves its head, alternates mouth opening, and changes eye state during contact. The upper hind limb makes larger movements in the longer side-rub interval. Around 03:42.6–03:43.1, the torso rolls farther toward supine and the paws lift. The view changes immediately afterward.

**[A]** Side petting and belly exposure need different actions. Start belly exposure from the current side pose. Release upper-limb contacts, roll the pelvis/thorax together but not rigidly, and curl the forepaws. Keep the head turned so the muzzle does not disappear through the chest or floor.

The dense study supports an **entry** into belly exposure, not a measured 90-frame continuous belly loop. A loop is a runtime design choice. Do not infer alternating forepaw frequency or a fixed tongue-extension percentage from the occluded footage.

### 5.7 Recovery and departure

Primary sheet: [03:43–03:46](hb5j2v10eYs/release_223.jpg).

**[V]** A UI wipe partly obscures the entry. Once visible, the dog rolls from its back/side toward chest-down, places its forelimbs beneath the chest, raises the front, brings the rear up, then steps and turns away. The visible recovery occupies roughly 03:44.1–03:45.2. Departure follows.

**[A]** Do not reconstruct the UI wipe as a pose interpolation. Begin from the visible post-wipe pose if matching the edited recording. For uninterrupted gameplay, provide a physically continuous side/belly → prone → stand route. Do not crossfade directly from inverted belly to a running cycle.

The existing side → sit → stand route can be a production fallback, but it is a different choreography. Mark that difference in review.

## 6. Food, water, and objects

### 6.1 Drinking, 10:27–10:45

Primary sheet: [10:28–10:32](hb5j2v10eYs/drink_628.jpg).

**[V]** A pale water-filled bowl appears. Huayra approaches from behind it, reduces speed, places her forepaws beside/behind the bowl, lowers her muzzle, then repeats small head motions. By around 10:29.3 the muzzle is at bowl height. The torso stays mostly horizontal and the hindquarters stay raised. Later she lifts her head and stops. The status screen around 10:51 reads thirst quenched while hunger remains hungry.

**[A]** Action chain: detect bowl → orient → approach → short alignment step → muzzle lower → `shiba_drink_loop` → muzzle lift → idle/sit. Start the loop only when the mouth target is over the water, not when the bowl first spawns.

Move `head` and upper body together enough to reach. Do not violate the `neck` seam policy to get all the reach from one joint. Keep front paws outside the bowl. Jaw/lap details are partly hidden by muzzle and rim, so a specific six-lap cycle is not measured evidence.

### 6.2 Eating, 10:55–11:19

Primary sheet: [10:58–11:02](hb5j2v10eYs/eat_658.jpg).

**[V]** The selected supply is Dry Food and the bowl visibly contains kibble. The dog takes a curved, turning approach rather than teleporting to the rim. The head lowers after alignment, approximately 10:59.3–10:59.9. Repeated muzzle/head motion follows with largely stable feet and back. Around 11:17–11:19 the head lifts and the dog becomes seated.

**[A]** Use a separate consume state from drinking. Share the approach/alignment machinery, but fit different head/jaw micro-motion only if visible. Preserve head-to-bowl contact height through the loop. Disable gaze that would pull the muzzle away while consuming.

Do not call the earlier water sequence eating. Do not make the dog sit to reach a floor bowl: both consume references use a standing, head-down posture.

### 6.3 Bubble Blower, 09:51–10:13

Primary sheet: [10:03–10:09](hb5j2v10eYs/bubble_play_603.jpg).

**[V]** The dog changes heading and moves toward the nearby bubble activity. Foreground bubbles and wand obscure much of its face and feet. The clearer frames around 10:06 and 10:08 show approach and lateral repositioning, not a complete verified catch or bite sequence.

**[A]** Implement target acquisition → short pursuit → stop/reorient → reacquire while bubbles remain. Select a visible world-space bubble target, not the HUD or the center of the screen. Suppress claims of measured jump height, snap timing, or bubble-pop causality because contact is hidden.

A tennis-ball supply is visible earlier in a menu, but this recording does not show a complete thrown-ball fetch. The later gift containing a Tennis Ball is also not a fetch demonstration.

### 6.4 Gift carry → paws-up presentation, 14:04–14:15

Primary sheet: [14:04–14:08](hb5j2v10eYs/gift_844.jpg).

**[V] Approximate phases:**

| Source time | Visible event |
| --- | --- |
| 14:04.1–14:04.6 | Gift held at muzzle, body approaches and aligns to viewer |
| 14:04.7–14:05.1 | Chest rises and both forepaws appear with pads toward viewer |
| 14:05.1–14:07.4 | Gift and paws held near camera. Small head/body changes and a blink-like eye closure |
| Around 14:07.5 | Gift disappears amid sparkle feedback, mouth opens wide |
| 14:09–14:13 overview | Paws-up presentation continues without gift while reward text is shown |
| Around 14:15 overview | Dog leaves the close presentation and route view resumes |

**[A]** Use `shiba_fetch_carry_loop` only as a locomotion starting point, then `shiba_paws_up_enter` → `shiba_paws_up_loop` → `shiba_paws_down`, with a separate object state. The carry jaw must suppress panting. Attach the gift at a mouth-relative grip transform. Trigger object removal at the presentation/reward event, not at an arbitrary animation end.

Do not open the jaw through the gift before release. Do not let generic gaze swing the gift through the camera. The hind support is offscreen during the close hold: do not claim a measured seated-vs-standing rear posture. Choose a stable rear-supported construction and verify a side view in Blender.

**Trigger:** found-item return is explicit in the dialogue. This is the strongest evidence for the near-camera paws-up action. It is not evidence that every whistle call must end with paws raised.

## 7. Outdoor investigation, stops, and settling

### 7.1 Ground investigation → squat → recovery

Primary sheets: [15:02–15:08](hb5j2v10eYs/sniff_902.jpg), [15:08–15:12](hb5j2v10eYs/squat_exit_908.jpg).

**[V]** The muzzle lowers progressively while the dog takes short steps. Around 15:03–15:04 it moves close to the ground. The body rotates, the muzzle rises, and the hindquarters compress around 15:05.7. The compact squat holds through approximately 15:09. A bag/cleanup graphic appears. The dog rises and reorients by approximately 15:09.5–15:10, then resumes movement.

**[I]** The sequence and cleanup graphic support elimination context. The exact physiology is not inferred from pose alone. Do not reuse a relaxed sitting loop and call it an exact squat.

**[A]** Create distinct phases: lower-head investigation with short steps → stop and adjust feet → compress hindquarters with forelimbs supporting → hold → rise → turn → gait. While sniffing, animate the nose target over a small ground patch without forcing every step to face directly forward. Preserve digitigrade hind limbs during the squat.

Existing clip inventory lacks a dedicated sniff-walk and elimination squat. Proposed actions: `shiba_sniff_ground_loop`, `shiba_squat_enter`, `shiba_squat_loop`, and `shiba_squat_exit`. These are additions for a future implementation, not files created by this study.

### 7.2 Outdoor pauses

The holds around 14:21–14:27 and 14:41 need their own contextual classification. They are visibly lower than ordinary standing, but an overview frame cannot distinguish refusal, rest, toileting, and a scripted stop by itself.

**[A]** For a reconstruction, replay the observed posture and duration within that scene. For autonomous gameplay, choose a documented trigger such as route stop or explicit rest. Do not invent a fatigue threshold and attribute it to the original game.

### 7.3 Return-home settling and sleep limits

**[V]** Around 15:47–15:53, the dog changes from standing to sitting to chest-down. The recording then switches to saving UI.

**[A]** Reuse sit/down transitions with reduced movement energy. Do not add a long sleep, dream twitch, yawn, or wake stretch to the reference inventory. Those actions exist in the project, but this footage does not establish their cycles or trigger timing.

## 8. Runtime trigger and transition matrix

This table separates observable cues from proposed application rules. It describes **when to use the reconstructed motions**, not recovered original source code.

| Scenario | Evidence/cue | Entry and motion [A] | Exit/interrupt rule [A] | Avoid |
| --- | --- | --- | --- | --- |
| Unattended room/kennel | Dogs wander and change posture behind UI [V] | Idle, look, short walk, optional sit/down/roll selected from valid posture | Finish support transfer before another locomotion state | Constant full-body fidget or one synchronized oscillator |
| Player calls from a distance | Whistle UI and approach, 02:53/03:03 [V] | Notice, orient with steps, approach target, decelerate, near standing | Pet contact takes priority once near. If already near, orient without running | Paws-up after every call |
| Voice naming/training input | Microphone UI, 04:24 onward [V] | Listening orientation and hold | Recognition result chooses acknowledgment, uncertainty, or release | Invented fixed freeze latency or automatic success |
| Uncertain recognition | Question-mark feedback and head tilt [V] | Brief tilt/attentive hold, then idle | New input can reacquire attention after current adjustment | Treating it as fear or a clinical emotional state |
| Head petting | Hand cursor intersects head [V] | Pet reaction layered on the current valid standing/sitting/prone posture | End the reaction when contact ends, then choose a posture-safe recovery | Resetting to standing for every stroke |
| Downward head gesture | Explicit sit tutorial [V] | Stand → sit, then seated hold | Training input can associate the completed action | Requiring six seconds of petting |
| Learned sit command | “Sit down” test around 09:15–09:19 [V] | Orient/approach if needed, then sit | Hold until interaction changes or ambient release | Instant seated teleport while walking |
| Continued gentle petting | Sit/down/side changes during contact [V], threshold unknown | Select eligible settle variant based on current pose and touched region | Allow rest to persist without endlessly restarting entry | Claiming 3 strokes/4 seconds or >6 seconds as original rules |
| Torso/belly contact while on side | Side rub and belly entry [V] | Side response, occasional upper-leg response, optional belly exposure | Recover through side/prone before standing | Standing scratch clip or rolling through floor |
| Close-interaction exit | View exit and physical recovery around 03:43 [V] | Recover then disengage/turn/walk | Locomotion starts after support is regained | Blending belly directly to run |
| Bowl placed | Care supply and visible bowl [V] | Detect → align → approach → lower muzzle | Consume only after arrival; stop if bowl removed or interaction ends | Starting eat/drink at spawn regardless of position |
| Water vs food | Water surface/status vs kibble and supply label [V] | Correct consume loop and resource type | Head lift before turning away; sit afterward if selected | Treating every bowl as food |
| Bubbles active | Bubble Blower and visible moving bubbles [V] | Target tracking and short pursuit | Reacquire/idle when target gone | Fabricated fetch-carry or bite events |
| Walk route active | Route confirmation and leash scene [V] | Route locomotion, glances, starts/stops | Stop for encountered context, resume via support-safe entry | One uninterrupted run loop across all route events |
| Found item | Gift return dialogue [V] | Carry → approach → paws-up presentation | Reward event releases gift; paws-down before route locomotion | Calling the gift a caught tennis ball |
| Ground investigation | Nose-down short stepping [V] | Ground target and short stride variant | Stop/squat if event selected, otherwise restore gait | Full-speed travel with nose scraping floor |
| Elimination/cleanup event | Squat plus bag graphic [V/I] | Investigation → squat hold → recovery | Complete stable rise before walking | Generic seated idle with no preparation |
| Post-walk rest | Return message and stand/sit/down sequence [V] | Sit then prone rest | New interaction routes from lying posture | Invented sleep/wake evidence |

### Arbitration and layer ownership [A]

Use the existing clip/runtime split rather than adding competing controllers.

1. **Base action owns support and posture.** Sitting, rolling, rearing, and recovery cannot be interrupted by an arbitrary standing pose.
2. **Travel owns the horizontal root parent.** Stop travel for planted consumption or a stationary presentation. Do not apply horizontal travel twice.
3. **Interaction owns attention targets.** Bowl/gift grip overrides generic cursor gaze while contact matters.
4. **Expression owns eye material and permitted jaw changes.** Suppress pant while gripping an object. An awake prone face differs from sleeping eyes.
5. **Secondary layers respect action masks.** Fade generic tail/ear/head noise out when the authored action supplies those beats.
6. **Gameplay events own prop/feedback changes.** Gift release, bowl removal, sparkle, and training icon do not belong to arbitrary bone rotations.

Suggested precedence: support-critical recovery/landing → object-contact action → explicit user posture command → pet response → ambient variation. This is a recommended reconstruction rule, not a measured original priority table.

Every action should declare entry posture, exit posture, contact set, loop behavior, safe interruption phases, target requirements, and owned channels. Existing filenames remain unchanged unless the shared contract is explicitly extended.

## 9. Reconcile the existing storyboard before authoring

Do not silently rewrite current production files from this analysis. These are reference corrections and implementation gaps.

| Existing assumption/specification | Evidence-aware correction |
| --- | --- |
| Video title implies Labrador performance | Primary adopted dog is explicitly Shiba Inu. Red coat differs from contract coat B |
| 40-frame walk / 28-frame run are reference timings | They are authored project values. Fit source cycles separately and account for duplicate loop endpoints |
| 0.55-duty diagonals provide suspension at the listed gaps | The stated half-cycle-offset contact schedule overlaps. Recompute actual contact occupancy before claiming flight |
| Walk always has three feet down at 0.65 duty | Four limbs × 0.65 = 2.6 average contacts. Continuous three-foot support is mathematically incompatible with that average |
| Head “lags” the body but therefore “leads” the turn | Those are opposite temporal claims. The 04:24 listening reference shows head aim before body alignment |
| Any call proceeds through fixed stun, curious, run, paws-up | Separate listening, approach, and gift-presentation contexts. The strongest paws-up evidence is the gift return |
| Side recovery always ends seated | 03:21–03:23 ends chest-down. 03:44 recovery proceeds through prone to stand |
| Side/belly transition can use one fixed global roll and height | Root offset must follow the floor-contact pivot. Check dependent limb and head collisions |
| A fixed pet timer or stroke count reproduces the original | Original threshold is unknown. Tutorial proves a specific downward gesture can cause sit |
| Closed eyes must always precede jaw opening by 150 ms | The sampled video supports combinations and transitions, not this universal latency |
| Tail is never static in calm wakefulness | Not established. Preserve observed pauses and distinguish projection changes from tail articulation |
| Happy wag always has a fixed rightward bias | Scientific context is not proof of game implementation. Match visible tail motion first |
| Hungry/thirsty means low tail and low energy | At 06:29 status shows hungry/thirsty, yet the dog still approaches and interacts. Do not hard-gate all engagement from needs |
| Care Book pages demonstrate live shampoo/brush animations | They are illustrated instructions. Do not treat them as a measured live sequence |
| Existing sleep, yawn, scratch, shake, stretch, fetch clips are all validated by this video | They are project actions. This study does not verify each against a visible source performance |

High-priority authoring gaps for closer reproduction: side-to-prone, belly/side-to-stand recovery, awake-prone petting, bowl approach/lower/lift transitions, ground investigation, squat/recovery, short rear-with-landing, and gift-specific presentation events.

Use existing actions where their entry/exit poses truly match. Do not duplicate a clip merely to change its gameplay trigger. Add a new action when support mechanics or terminal posture differs.

## 10. Blender reconstruction procedure

### 10.1 Set up the reference, not a speculative rig rewrite

1. Import a copy of the source DAE through the existing Blender 4.2 pipeline.
2. Verify 28 names and the unchanged skin/material identity.
3. Establish +Y source-up and +Z source-forward with the rest positions in §2. Do not infer this from the export dropdown.
4. Keep the original deform rig untouched. Add removable controls only if needed.
5. Use the source video as a movie reference or image sequence. Work in seconds when aligning a 59.94 fps source with 30 fps actions.
6. Crop the active game pane. The dog changes from left pane to right pane across UI transitions. Do not track the wrong pane.
7. Match the camera for each shot before matching poses. Use the floor and standing silhouette to establish framing.

The central active strip in this inspection copy is approximately Y=180–900. Each pane is 960 × 720. Close-study sheets crop that strip and one pane, then resize to 320 × 240 per cell. Screenshots show rendered game geometry, not original texture-resolution detail.

### 10.2 Pose-fitting order

**First pass:** root, pelvis, chest, and visible paw contacts. Use flat viewport shading or a silhouette render.

**Second pass:** fore/hind articulation, head aim, body turn, and contact adjustments. Preserve support throughout the transition.

**Third pass:** eyes, jaw, ears, and tail. Place their changes relative to body events, not one global sine wave.

**Fourth pass:** small secondary motion. Add only movement visible in the selected reference or explicitly marked as an authored substitute.

For each key pose, annotate: source time, local action frame, support set, pelvis/chest height relative to standing, head direction, eye state, jaw state, ear silhouette, tail silhouette, and uncertainty. Measure displacement relative to standing shoulder height rather than inventing centimeters.

### 10.3 Timing and curves

At 30 fps, map a source event at time `s` relative to clip start `s0` to `F = 1 + round(30 × (s - s0))`. Keep the unrounded source time in notes. The one-frame uncertainty introduced by authoring quantization is separate from video sampling uncertainty.

- Start with stepped key poses to verify support and action order.
- Use smooth interpolation for body mass, but clamp overshoot near floor and bowl contact.
- Keep world-space planted paw trajectories flat through contact.
- Use short asymmetrical adjustments where observed. Do not mirror every key mechanically.
- Close loops in both pose and velocity. A duplicate first/last pose alone does not eliminate a velocity hitch.
- Separate entry, hold, and exit. Never extend a one-shot settling action by looping the entire fall.
- Avoid time-scaling locomotion without matching root speed. A faster stride cycle needs corresponding travel speed or a reduced stride.

### 10.4 Face and prop delivery

Skeletal DAE alone cannot reproduce eyelid closure because this rig has no eyelid bones. Deliver a synchronized expression/event track or use the existing runtime face-state mechanism. State whether a preview includes those layers.

For a gift or carried object, verify attachment under animated scale and rotation. The project contract already documents inherited bone-scale issues for mouth attachments. Do not diagnose that by changing the dog's proportions.

If the renderer cannot export material animation through this DAE path, keep eye state and object release as explicit runtime events. A Blender viewport with closed eyes does not prove the application will show them.

### 10.5 Export through the current contract

- Blender 4.2 LTS.
- Original armature and mesh only.
- One action per file.
- 30 fps, sampled at every frame, matrix transforms.
- Keep the existing Y-up/−Z-forward conversion settings and original channel mapping.
- No applied modifiers, triangulation, geometry changes, re-parenting, or bone renames.
- Preserve `eye` and `hand` material-name substrings for current material reassignment.
- Horizontal locomotion stays in place. Runtime moves the parent. Vertical body motion remains permitted per contract.

Use the repository's existing authoring/export/verification tools. This research session did not regenerate clips or certify the present exports against the reference.

## 11. Acceptance and modeller handoff

### Evidence pack

All retained sheets are linked below. They contain source footage excerpts, not Blender renders. Keep them with the private project and do not redistribute Nintendo assets or the recording.

| Sheet | Window | Sampling | Main question |
| --- | --- | --- | --- |
| [approach_184](hb5j2v10eYs/approach_184.jpg) | 03:04–03:08 | 6 Hz | View change, frontal travel, near stop |
| [roll_197](hb5j2v10eYs/roll_197.jpg) | 03:17–03:23 | 4 Hz | Sit-to-side and side-to-prone |
| [belly_219](hb5j2v10eYs/belly_219.jpg) | 03:39–03:45 | 4 Hz | Face response and belly entry |
| [release_223](hb5j2v10eYs/release_223.jpg) | 03:43–03:46 | 8 Hz | Recovery and departure after view wipe |
| [alert_264](hb5j2v10eYs/alert_264.jpg) | 04:24–04:27 | 8 Hz | Head-before-body orientation |
| [sit_407](hb5j2v10eYs/sit_407.jpg) | 06:47–06:51 | 6 Hz | Sit with asymmetric paw placement |
| [down_414](hb5j2v10eYs/down_414.jpg) | 06:54–07:00 | 4 Hz | Forepaw reach and chest lowering |
| [gesture_sit_460](hb5j2v10eYs/gesture_sit_460.jpg) | 07:40–07:43 | 8 Hz | Explicit downward-gesture sit |
| [bubble_play_603](hb5j2v10eYs/bubble_play_603.jpg) | 10:03–10:09 | 4 Hz | Pursuit with heavy foreground occlusion |
| [drink_628](hb5j2v10eYs/drink_628.jpg) | 10:28–10:32 | 6 Hz | Water approach and muzzle placement |
| [eat_658](hb5j2v10eYs/eat_658.jpg) | 10:58–11:02 | 6 Hz | Curved food approach and head lowering |
| [gait_814](hb5j2v10eYs/gait_814.jpg) | 13:34–13:36 | 12 Hz | Forequarter lift, landing, travel |
| [stride_819](hb5j2v10eYs/stride_819.jpg) | 13:39–13:41 | 12 Hz | Side-view limb cycle and head independence |
| [gift_844](hb5j2v10eYs/gift_844.jpg) | 14:04–14:08 | 6 Hz | Carry, rear, hold, object release |
| [sniff_902](hb5j2v10eYs/sniff_902.jpg) | 15:02–15:08 | 4 Hz | Nose-down stepping and squat entry |
| [squat_exit_908](hb5j2v10eYs/squat_exit_908.jpg) | 15:08–15:12 | 6 Hz | Cleanup context and recovery |

### Reference verification

The [evidence manifest](hb5j2v10eYs/evidence-manifest.json) records sampling windows, pane selection, stream properties, and SHA-256 hashes. All 16 retained images decoded successfully. The report's local evidence links resolved, and all 45 timestamp links fell within the recording. The rig map matched all 28 source joint names. STE-flavored prose lint scored 1.75 findings per 100 words before this verification note. This verifies the research package, not a Blender reconstruction.

The inspection video was copied to the private DavidOS Google Drive vault at `30_Media/Video/2026/nintendogs-hb5j2v10eYs.mp4`. It is not stored in this repository.

### Reconstruction review gates [A]

1. **Sequence:** compare the action order against the timestamp inventory. Side-to-prone must not become side-to-sit without an explicit compromise.
2. **Timing:** compare anticipation, change, hold, and exit in seconds. Exclude dialogue holds when measuring locomotion cycles.
3. **Silhouette:** compare root height, chest/pelvis relationship, muzzle direction, ear shape, paw spread, and tail curl at the retained poses.
4. **Contact:** inspect every exported frame around footfall, lowering, rolling, bowl contact, and recovery. Check paw vertices, not only bone origins.
5. **Sliding:** in a ground-fixed preview, planted paws should remain stable except for the observed repositioning steps. A moving camera is not proof of no slide.
6. **Seams:** inspect neck, tail root, shoulders, and hips at the strongest pose from at least front, side, and three-quarter views.
7. **Face:** verify eye state, jaw, and ear combination both in Blender and in the actual consumer. Check carry suppresses panting.
8. **Transitions:** run the exact chains with the real blend times. A clean individual action is insufficient if its transition lifts a planted paw or twists the root.
9. **Triggers:** exercise call while far and near, pet while standing/seated/prone, downward gesture, bowl placement, gift release, interruption, and route resume.
10. **Claims:** record measured matches separately from rig-limited approximations and unknown hidden motion. Do not label the result “exact original animation.”

Suggested numerical review targets, **not observed source values**: planted-paw drift under 1% of standing shoulder height during a clean stationary contact, floor penetration under 0.5% where the surface is rigid, and key event timing within one 30 fps frame after full-rate manual alignment. These targets need adjustment if the source intentionally slides or if a contact is ambiguous.

**Recommended production order:** contact-correct approach/side travel → sit/down and awake pet face → side/prone/belly recovery → drinking/eating alignment → gift presentation → outdoor sniff/squat → optional background variations. This order addresses the most visible evidence first, not the easiest clip names.

**Handoff:** reference analysis and evidence are complete. Animation re-authoring is not part of this deliverable. Next owner: Blender modeller. Next action: block `shiba_sit` against 06:48 and the side-to-prone transition against 03:21, then compare matched-camera renders before adding secondary layers. David retains visual acceptance.

## 12. Sources and skills used

### Primary visual and project sources

- [Octetra recording](https://www.youtube.com/watch?v=hb5j2v10eYs). Source for the observed performances and on-screen tutorial text.
- [Animation contract](../ANIMATION_CONTRACT.md). Source for immutable names, file delivery, seam safeguards, and current runtime responsibilities.
- [Animation storyboard](../ANIMATION_STORYBOARD.md). Existing authoring conventions and hypotheses. Not independent proof of video timings.
- `mac/Assets/shiba/aSib_b.nsbmd/Sib_b.dae`. Original static source rig.
- `blender/clip_pipeline.py`, especially source matrix composition and `set_pose`. Source for quaternion basis conversion and export settings.

### Biomechanics and interpretation

- [Fischer et al., 2018 — Three-dimensional kinematics of canine hind limbs](https://pmc.ncbi.nlm.nih.gov/articles/PMC6242825/). Biplanar fluoroscopy across four breeds. Supports three-dimensional articulation, breed variation, stance/swing structure, and caution about estimating bone motion from external appearance. Its measured angles are **not** Shiba game-rig values.
- [Kim et al., 2015 — Kinetic and temporospatial gait parameters in a heterogeneous group of dogs](https://pmc.ncbi.nlm.nih.gov/articles/PMC5015230/). Defines duty factor and measures gait/size-related differences and fore/hind load distribution. Approximately 60/40 fore/hind distribution in that study is background mechanics, not a measured force split in this game.
- [RSPCA — Understanding a dog's body language](https://www.rspca.org.uk/adviceandwelfare/pets/dogs/behaviour/understanding). Supports interpreting ears, eyes, mouth, tail, and posture together. Similar signals can occur in different contexts.
- [Siniscalchi et al., 2013 — Seeing left- or right-asymmetric tail wagging produces different emotional responses in dogs](https://doi.org/10.1016/j.cub.2013.09.027). The indexed abstract was examined through Europe PMC. Supports context-sensitive tail communication, not a mandatory right-biased game animation.

No universal canine freeze duration, blink interval, gait period, petting threshold, or hidden Nintendogs decision probability was established by these sources. Broad search service access failed, so known primary-source URLs and Europe PMC's public API supplied the supporting literature. The video itself supplied the game tutorial evidence.

### Skills selected and applied

- **find-skills:** searched the skill directory for Blender animation and video analysis rather than installing unrelated UI/generation tools.
- **web-research:** separated visual, rig, and biological evidence. Used independent research slices, then verified the important claims against direct evidence.
- **blender-web-pipeline:** used asset-preservation, sampled-action, and consumer-verification principles. Its generic glTF optimization recipes were **not** applied because this project requires unchanged Collada assets.
- **[blender-motion-state-inspection](https://skills.sh/affaan-m/ecc/blender-motion-state-inspection):** read the full skill and applied structured rig/axis/contact inspection before interpreting rendered poses. This did not require installing or running external code.
- **[ffmpeg-analyse-video](https://github.com/fabriqaai/ffmpeg-analyse-video-skill):** read the frame-extraction workflow and adapted it to dense action windows. Reviewed the instructions directly rather than executing a third-party script. Sparse overview sampling alone was not accepted as motion proof.
- **ste-writing, STE-flavored:** used direct procedures, consistent control names, and explicit uncertainty in the modeller handoff.

No generative-video skill was used: generating plausible replacement motion would weaken, not strengthen, fidelity to the supplied footage. No browser or GUI window was opened. No rig, action, production code, or existing animation contract was modified.
