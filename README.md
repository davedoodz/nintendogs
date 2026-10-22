# Nintendogs (fan recreation)

```
        _......._
      .'  o   o   `.
     /    .--.      \
    |    ( __ )      |      woof?
     \    `--'      /
      `.___⌣_____.'
       /  |   |  \
      (___)   (___)
```

A fan-made, from-scratch recreation of the Nintendo DS Nintendogs (2005) feel: a 3D puppy you pet, wash, walk, and name, with the DS-era soft-lit look.

No original Nintendo assets or code are used anywhere in this repo. Everything is built new, from scratch, as visual reference only.

## Status

Planning. This repo currently holds a one-week design sprint, scoped day-by-day, and the research behind it — no app code yet.

## Why web first

The sprint picked **web (Three.js / React Three Fiber + Vite)** over a native Swift app for the prototype phase: faster iteration, a native glTF pipeline from Blender, and a trivial path to DS-era flat/toon lighting. Swift (SwiftUI + RealityKit) wins on haptics, on-device speech, and App Store distribution, so it's the candidate for a later port if the prototype proves the idea out. The full criterion-by-criterion comparison is in `docs/PLATFORM_ASSESSMENT.md`.

## The sprint

Five working days, Google Ventures style, compressed to one person plus AI agents for asset generation, code, and headless verification:

1. **Map and target** — user journey, art direction, scaffold (Vite + React + R3F + drei + zustand), first puppy concept art.
2. **Sketch and decide** — interaction model for petting and washing, Blender low-poly puppy model and rig.
3–5. Build toward the target moment — first pet — through naming, the home scene, wash mode, and playtesting.

Done when: a puppy idles, looks at the cursor, reacts to petting; wash mode has a working sponge/bubble/rinse/shake loop; naming persists across reloads; headless screenshots of the three core screens exist; three people have playtested it; and a go/no-go decision on a Swift port is recorded.

Non-goals for the sprint: walking outside, competitions, shopping, multiple dogs, multiplayer, and any App Store submission.

## Docs

- `docs/PLATFORM_ASSESSMENT.md` — Swift native vs. web, scored criterion by criterion.
- `docs/SPRINT_PLAN.md` — day-by-day plan for the one-week sprint.
- `docs/ART_DIRECTION.md` — palette, camera, UI chrome decisions, plus a fan-preservation reference list (The Spriters Resource, TCRF, the Nintendogs fan wiki) kept strictly as *look-only* visual reference — nothing from those sources is imported, traced, or shipped.

## Prior art check

Searched GitHub, Google, X/Nitter, Bing, and DuckDuckGo (2026-09-14) for an existing Swift/iOS recreation with matching 3D graphics. Found a 3DS save editor, a Java virtual-pet toy, a browser 2D clone, and a Unity VR project — none a close match. This project fills that gap.
