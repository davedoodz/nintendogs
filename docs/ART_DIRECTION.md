# Desktop care-game art direction

## Current brief

Recreate the interactions shown in the two Nintendogs references in a single desktop viewport. The user subsequently replaced dogs with Pikachu, Mudkip and Charmander, retaining the textured 3D character system. Working display title: Poképals. Repository remains `nintendogs`.

## Reference evidence

- Part 1: https://www.youtube.com/watch?v=hb5j2v10eYs — 16:10. Creator chapters: 0:00 intro, 0:30 buying a puppy, 2:34 home, 4:10 naming, 6:23 first trick, 9:35 playing/feeding, 11:40 Care Book, 13:00 walking.
- Part 2: https://www.youtube.com/watch?v=7iOVyk8pwWQ — 11:18. Visually sampled at 20-second intervals: shopping and supplies, sponge and shower bath, street-route drawing, night walk, present, neighbor encounter, return home, water/food, brush and sit, contest entry restriction, tennis ball, bubble blower, save confirmation.

Part 1 was visually sampled every 30 seconds. Chapter times are from metadata, not exact manually measured transitions. Do not label sample-based reconstruction as frame-perfect reproduction.

## Desktop mapping

| Original | Desktop |
| --- | --- |
| Upper 3D view / lower touch/menu screen | One full-window 3D scene with overlaid menus and dialogue |
| Date/clock screen | Compact persistent header |
| Gold call icon | Gold call button in lower HUD |
| Stylus petting | Pointer drag over the actual model surface |
| Voice name learning | Text entry followed by three explicit name calls |
| Sit gesture and repeated voice command | Downward drag or S, repeated three times, then command text |
| Supply category/item screens | Centered cream panel, warm beveled header, orange back button |
| Bath items | Sponge/shower toolbar and lather/rinse meter |
| Lower-screen walk map | Route-planning panel; timed walking events in the main scene |
| DS save dialog | Yes/No confirmation and browser-local save |

## Visual system

- Quiet ivory shell, warm timber floor, pale plaster, dark window frames and a green garden.
- Green action controls, warm cream/yellow dialogue and panel headers, orange back controls, gold call button.
- UI stays legible at desktop size rather than magnifying entire DS screenshots.
- Rounded Verdana/Trebuchet-style sans-serif; dark olive text; no web-font dependency.
- Pet is the focal point in the room, with menu on the left and dialogue below.
- Model textures stay visibly textured rather than becoming smooth, generic PBR objects.
- One world scene; no fake handheld frame, split screens, landing page or dashboard card grid.
- Reduced-motion media preference suppresses nonessential interface motion.

## Assets

Original Nintendogs UI sounds, care-book art, bathroom sheet and walk map are local assets. Pokémon models and their textures come from one PokéPark Wii extraction collection. All three are COLLADA models, loaded with Three.js ColladaLoader; no Blender conversion required. Portrait sprites come from PokeAPI's sprite archive.

See README for exact source links. The historical no-original-assets rule has been superseded by the user's explicit asset request, but the assets remain copyrighted and are not licensed by this project. This is a local, unofficial study; do not infer permission to redistribute or deploy it publicly.

## Deliberate differences from original gameplay

Original animation clips are not present in the downloaded models. Idle, look, walk and reactions are procedural adaptations. Naming is not speech recognition. Walks are condensed, use a small connected street loop and grant prototype currency. The videos only show the contest menu/entry restriction: the build provides those checks and a practice field, not a fabricated recreation of a judged competition absent from the references.

## Original reference archives

- DS dog models (reference only after Pokémon change): https://models.spriters-resource.com/ds_dsi/nintendogs/
- DS textures: https://textures.spriters-resource.com/ds_dsi/nintendogs/
- DS sprites: https://www.spriters-resource.com/ds_dsi/nintendogs/
- UI audio: https://sounds.spriters-resource.com/ds_dsi/nintendogs/asset/437715/

Reusable original-art alternatives for a future independently licensed release: https://kenney.nl/assets (check the chosen pack's license) and https://game-icons.net/ (attribution required under its stated license). These are alternatives, not sources of the current Pokémon characters.
