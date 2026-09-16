# nintendogs / Poképals

**Direction change (2026-09-16):** the product is now a native macOS desktop pet — one Nintendogs Shiba that lives on the Mac, sleeps, eats, begs, fetches into depth and needs feeding and walking. The one-week build plan lives in the Obsidian vault at `projects/nintendogs-mac-pet-plan.md`. The earlier browser study remains as reference for flows and asset provenance.

## Native macOS spike

Confirmed direction: **SceneKit, a Shiba Inu, and Blender animation clips authored by David**.

```sh
npm install
npm run assets:mac
mac/scripts/bundle.sh release
```

Bundle: `mac/build/Nintendogs.app`. It contains the local Shiba models and textures, so it does not need the repository beside it. macOS 14+; the current build targets the host architecture. The bundle is ad-hoc signed for local use, not notarized or distributed.

Implemented: a menu-bar app, borderless floating non-activating panel, transparent SceneKit view, fixed camera, lighting, blob shadow, model normalization, explicit black-and-tan Shiba coat-B texture assignment, and show/hide/rotate controls. Clicking the Shiba rotates it 90°; dragging the panel still moves the window. **No autonomous behavior, care loop, or authored animations yet.**

The release build, signature verification and plist validation pass. A fresh `npm run assets:mac` download was verified in a temporary directory, including all three coats and their textures. All 12 asset files in the bundle match the source files.

`swift test` is currently blocked: the Command Line Tools installation lacks both XCTest and Swift Testing. Full Xcode is installed but requires license acceptance. The package includes a rig/normalization regression test for a toolchain with Swift Testing.

Installed Blender 5.2.1 has no Collada import operator. The animation-authoring import/export workflow must therefore be validated before David authors clips; do not assume the earlier plan's direct DAE round trip works. The failed conversion experiment was removed.

With David's explicit permission, the packaged app was launched and its own window captured. The requested black-and-tan coat-B Shiba renders with a black body, tan eyebrows/cheeks/legs, and white muzzle/chest/paws. The PNG has transparent background pixels (corner alpha 0). An actual mouse drag moved the panel while Chrome remained the frontmost app; the original panel and cursor positions were restored. A real click on the Shiba rotated the model 90° to the reference side profile. Three two-second-spaced idle samples reported 0.0% CPU and 87.2 MB resident memory. This proves the static U1 scene, not animation performance or a long-duration soak. Evidence: `docs/screens/native-shiba.png`.

A standalone SceneKit loader returned `NSCocoaErrorDomain 257` / `EPERM` even though ordinary Foundation reads succeeded; the packaged application loads the same DAE successfully. The cause of the standalone failure remains unconfirmed.

## Browser study (reference only)

A local desktop-web care-game study: Nintendogs-style interactions with Pikachu, Mudkip and Charmander. One integrated 3D scene replaces the DS dual-screen layout. Built with Vite, JavaScript and Three.js.

## Run locally

```sh
npm install
npm run assets
npm run dev -- --port 5173
```

Open http://127.0.0.1:5173/. `npm run build` creates `dist/`; `npm run preview` serves it locally. WebGL is required. Audio begins after a user action. Progress is stored in this browser's localStorage, not a server or account.

Node 20.19+ and `unzip` are required. `npm run assets` downloads the linked copyrighted media into ignored `public/assets/`; review the rights note before doing so. Already-present assets are reused. A source checkout without that local asset step cannot render the companions.

## Current implementation scope

- Choose one of three textured, skeletal 3D Pokémon; adopt, settle in, name and call them.
- Learn a sit command through repeated gestures (keyboard S also works).
- Home, status, supply categories, food, water, brush, shampoo/sponge/shower, ball and bubbles.
- Care-book pagination with original Nintendogs illustration sprites.
- Shopping, inventory counts and secondhand sales.
- Street-route selection, walking, gift and greeting events, return home.
- Contest requirement checks and a practice field; the reference videos do not show a complete judged contest.
- Explicit save confirmation and automatic progress persistence.

## Verification — 2026-09-15

- `npm run assets` completed; `npm run build` passed. Vite reports a 625 kB minified JavaScript chunk (166 kB gzip), mostly the Three.js renderer and COLLADA loader; this is a size warning, not a build failure.
- Headless Chromium exercised adoption, name learning, sit training, food/water, sponge/shower, brushing, ball fetch, bubbles, buying/selling, contest restrictions, care-book pagination, a complete walk with both events, and explicit save/reload.
- Regression checks covered closing Help during the tutorial, retaining partial/completed sit practice, restoring the adopted companion after kennel previews, and persisting greeting affection immediately.
- Screenshots inspected at 1365×768, 800×720 and 390×844. Narrow layouts were checked for horizontal overflow; the portrait camera keeps the companion in frame.
- The final browser pass recorded no page exceptions or asset responses with HTTP status 400 or higher. Visual evidence is in `docs/screens/`.

Built locally; not deployed or visually accepted by David. The current preview is http://127.0.0.1:5173/ while the development server is running. Audio requests were exercised, but audible playback was not assessed in the headless browser. No Safari/device performance claim is made.

## Reference and adaptation

Source videos: [Part 1](https://www.youtube.com/watch?v=hb5j2v10eYs), [Part 2](https://www.youtube.com/watch?v=7iOVyk8pwWQ), Octetra.

Both videos were downloaded to temporary storage for visual inspection. Contact sheets sampled part 1 every 30 seconds and part 2 every 20 seconds. These are not full frame-by-frame fidelity measurements.

Desktop adaptations: naming uses text and a call button instead of voice recognition; pointer drag and keyboard gestures replace the stylus; the route planner overlays the room instead of occupying a second screen. Walk event timing is compressed. Completing a walk grants $100 in this prototype so all three companions can be adopted without an unrelated grinding system. Room geometry and character reactions are newly implemented, not original extracted environments or animation clips.

## Asset provenance and rights

The latest user brief explicitly supersedes the earlier planning-only restriction on original assets. This local study now uses extracted game assets. They are **not open source** and this repo does not grant rights to publish, redistribute or commercialize them. No public deployment or asset redistribution is authorized by the local preview.

The Nintendogs Shiba rip under `mac/Assets/shiba/` and the clips authored from it are committed so the Mac and Windows machines share one state. That only works because the repo is private; it must stay private.

| Used asset | Source |
| --- | --- |
| Pikachu model and textures | https://models.spriters-resource.com/wii/pokeparkwiipikachusadventure/asset/284743/ |
| Mudkip model and textures | https://models.spriters-resource.com/wii/pokeparkwiipikachusadventure/asset/285740/ |
| Charmander model and textures | https://models.spriters-resource.com/wii/pokeparkwiipikachusadventure/asset/284772/ |
| Nintendogs Shiba models and textures (coats A/B/C) | https://models.spriters-resource.com/media/assets/313/316384.zip |
| Nintendogs menu/UI sounds | https://sounds.spriters-resource.com/ds_dsi/nintendogs/asset/437715/ |
| Care-book illustrations | https://www.spriters-resource.com/ds_dsi/nintendogs/asset/73785/ |
| Walk-map sheet | https://www.spriters-resource.com/ds_dsi/nintendogs/asset/83415/ |
| Bathroom texture sheet | https://textures.spriters-resource.com/ds_dsi/nintendogs/asset/374972/ |
| Character portrait sprites | https://github.com/PokeAPI/sprites |

Archive credit files are retained with the models. Copyright belongs to Nintendo, The Pokémon Company, Creatures, Game Freak and the relevant rights holders. This is unofficial and unaffiliated. Models are from PokéPark Wii, not DS Pokémon games; the rendering aims for the older textured, low-poly feel. There are no source animation clips in these model archives; reactions use procedural skeletal animation.

## Planning documents

- `docs/ART_DIRECTION.md`: current visual direction, observed video flows and adaptation decisions.
- `docs/SPRINT_PLAN.md`: original five-day planning brief; superseded where it conflicts with the current desktop/Pokémon brief.
- `docs/PLATFORM_ASSESSMENT.md`: historical platform comparison, not a measured benchmark. The app uses Three.js directly rather than the earlier proposed React stack.
- `docs/ANIMATION_CONTRACT.md`: the Blender (Windows) ↔ SceneKit (Mac) interface — rig, clip list, export settings, ownership, sync.

Prior research found no matching Swift recreation in the searches performed. This is not proof that none exists; X search was login-blocked and repository descriptions do not establish graphics or implementation details.
