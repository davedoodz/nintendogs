# One-week design sprint: nintendogs

Format: Google Ventures style, compressed. Five working days, one person (David) plus AI agents for asset generation, code, and headless verification. Platform: web (see `PLATFORM_ASSESSMENT.md`).

## Outcome

A playable web prototype where you meet a 3D puppy, name it, pet it, and wash it, that looks unmistakably like DS-era Nintendogs, and that three outside people have played.

## Done when

- `npm run dev` serves a scene with a rigged low-poly puppy that idles, looks at the cursor/finger, and reacts to petting.
- Wash mode: drag a sponge, soap bubbles accumulate, rinse clears them, puppy shakes off.
- Name entry persists across reloads.
- Headless screenshots of the three core screens live in `docs/screens/`.
- Three playtest notes in `docs/playtests.md`.
- Decision recorded in `docs/DECISION.md`: port to Swift, keep web, or stop.

## Non-goals

- Walking outside, competitions, shopping, multiple dogs, multiplayer.
- Any original Nintendo assets, sounds, fonts, or names.
- App Store submission.

## Day-by-day

### Day 1 (Mon): Map and target

- Morning: write the long-term goal and sprint questions in `docs/DECISION.md` (open).
- Study the reference screenshots (`docs/reference/`): top-screen clock/date panel, bottom-screen scene, menu button, item tray. Write `docs/ART_DIRECTION.md`: palette, lighting, camera height, UI chrome, font choice.
- Map the user journey: Launch -> meet puppy -> name it -> home scene -> pet / wash -> menu.
- Pick the target moment: **first pet**. Everything else supports it.
- Scaffold: Vite + React + `@react-three/fiber` + `@react-three/drei` + `zustand`. Commit.
- Evening: generate puppy concept sheets with Higgsfield (`higgsfield-generate`, GPT Image 2) for one breed (Shiba, matching the reference). Pick one.

### Day 2 (Tue): Sketch and decide

- Crazy 8s on paper for the home screen and wash screen; photograph into `docs/sketches/`.
- Decide the interaction model for petting: circular drag over the head/back raises a happiness meter and triggers a lean-in animation.
- Decide the wash loop: sponge drag spawns bubbles as instanced sprites on the puppy's surface; shower-head drag clears them; full clear triggers shake-off.
- Produce the puppy model: Blender low-poly Shiba (~2-4k tris), rig with a basic armature, animations: idle, look-at (procedural head bone), lean-in, shake-off. Export GLB. If modelling stalls past noon, buy or use a CC0 low-poly dog and retarget.
- Storyboard the six screens in Paper (MCP), export PNGs to `docs/storyboard/`.

### Day 3 (Wed): Build the scene

- Load GLB, toon material, soft directional light, warm ambient, baked-looking floor and wall.
- Camera: fixed, slightly low, matching the DS bottom-screen angle.
- Procedural look-at: head bone tracks the pointer with damping.
- Petting: pointer move over puppy mesh with raycast, accumulate "affection", drive lean-in blend and a small heart particle.
- UI chrome: top panel with date/time and puppy name card; bottom-left menu button; bottom-right item tray. Style from `ART_DIRECTION.md`.
- Headless verification: Playwright script `scripts/shots.ts` that opens the dev server, waits for the scene, and saves screenshots to `docs/screens/`. Run it at end of day.

### Day 4 (Thu): Wash mode and polish

- Wash mode toggle from the item tray.
- Sponge tool: drag spawns bubble sprites at the raycast hit, stuck to the puppy's local space.
- Shower tool: drag removes bubbles in a radius; when empty, play shake-off and reward hearts.
- Audio: bark on tap, squeak on sponge, water loop on shower; unlock on first tap.
- Name entry screen with persistence (localStorage).
- Performance pass: keep under 5ms frame time on an iPhone 13-class device in Safari; cap bubbles at 300.
- Re-run headless screenshots. Deploy preview (Vercel or Cloudflare Pages) so the URL is shareable.

### Day 5 (Fri): Test and decide

- Three playtests, five minutes each, on the tester's own phone via the preview URL. Script: "Here is a puppy. Do whatever you want." Observe silently for two minutes, then ask: What is this? What did you want to do that you could not? Would you open it again tomorrow?
- Log notes in `docs/playtests.md`.
- Afternoon: fix the top two observed problems only.
- Write `docs/DECISION.md`: answer the three questions from the platform assessment; choose port to Swift, keep web, or stop; list the next three concrete tasks.
- Final commit, tag `sprint-1`.

## Roles

- David: art direction, interaction decisions, playtests, final decision.
- AI agents: scaffold, R3F scene code, Playwright screenshot script, asset generation prompts, Blender export scripts, sketch cleanup.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Puppy model takes more than a day | Hard stop at Day 2 noon; fall back to CC0 low-poly dog |
| Rig/animation retarget fails | Use procedural bone animation (look-at, lean, shake) instead of baked clips |
| Petting feels flat without haptics | Compensate with squash-and-stretch, sound, and hearts; note for Swift port |
| iOS Safari audio unlock breaks first impression | First screen is "tap to wake puppy" |
| Nintendo IP nervousness | No original assets, new breed design, new name; keep repo private until decision |

## Tooling checklist

- Node 20+, pnpm
- Blender 4.x
- Higgsfield CLI (`higgsfield auth login`)
- Playwright (`pnpm dlx playwright install chromium`)
- Paper MCP for storyboards
