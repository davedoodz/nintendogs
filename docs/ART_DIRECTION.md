# Art direction reference

Produced Day 1 of the sprint (see `SPRINT_PLAN.md`). Palette, type scale, camera, and UI chrome decisions go here as they're made. This file starts with the reference material gathered for that work.

## Legal note

Everything in "Fan-preservation reference" below is ripped/extracted from the actual copyrighted Nintendogs DS ROM. Nintendo owns every pixel. Use these **only as visual reference** — proportions, palette, poly count feel, UI layout — while designing our own assets. Never import, trace, retexture, or ship any file from these sites in this repo. That would contradict the "no original Nintendo assets" rule in `README.md` and risks a takedown. Build everything here from scratch (own Blender models, own UI mockups, own icon set).

## Fan-preservation reference (look only, don't copy)

The Spriters Resource network, Nintendogs (DS/DSi), verified live 2026-09-14:

- **Models** (109 assets — rigged low-poly dog + item models): https://models.spriters-resource.com/ds_dsi/nintendogs/
- **Textures** (39 assets — 20 dog breed texture sheets, toys, bathroom, misc props): https://textures.spriters-resource.com/ds_dsi/nintendogs/
- **Sprites / UI** (13 assets — training-book UI panels, title screens, menu, walk maps): https://www.spriters-resource.com/ds_dsi/nintendogs/
- **Sounds** (menu/UI SFX): https://sounds.spriters-resource.com/ds_dsi/nintendogs/

Standouts to study:
- The 20 dog breed models/textures — proportions and shading style for our low-poly Shiba.
- Shower Head and Sponge models (assets 323046 / 323047) — directly maps to the Day 4 wash mode.
- The 7 training-book UI panels (Agility, Care, Contest, Tricks, Disc, Internet, Bottom Page) — closest match to the DS chrome/menu style in our reference screenshots.

Other fan documentation (not fetchable by automated tools due to bot protection; open manually):
- The Cutting Room Floor, unused/obscured graphics and dev leftovers: `tcrf.net/Nintendogs` and `tcrf.net/Nintendogs/Obscured_Graphics`
- Nintendogs Fandom Wiki, Development page, scrapped HUD designs and alternate touchscreen intros: `nintendogs.fandom.com/wiki/Development`

## Legitimately reusable assets (safe to ship)

- **Kenney.nl** — CC0 game UI icon packs, no attribution required: https://kenney.nl/assets
- **game-icons.net** — CC BY 3.0 SVG icon set
- Our own Blender low-poly Shiba (Day 2), informed by proportions observed above, never traced from them

## Open (fill in during Day 1)

- Palette
- Type scale / font choice
- Camera height and angle
- UI chrome layout (top panel, menu button, item tray)
