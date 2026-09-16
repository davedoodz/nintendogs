Blender 4.2 LTS working files and scripts (Windows side). Contract: docs/ANIMATION_CONTRACT.md

- `STEP0_RESULT.md`: corrected tail2 yaw test and source-basis export conversion.
- `CLIPS_RESULT.md`: 12-clip manifest, rigid-skinning constraints and validation.
- `shiba_test_tailwag.blend`: 30-frame test, tail1 stationary.
- `shiba_clips.blend`: all 12 contract actions; idle active on open.
- `step0_tailwag.py`, `author_clips.py`, `verify_clips.py`: rebuild and verification.
- `shiba_clips_tier2.blend`: 12 second-tier actions, separate from the accepted base set.
- Pass `-- --tier2` to `author_clips.py` / `verify_clips.py` for the second tier.
- `tier2_clips.py`: second-tier poses and checks against accepted handoff states.
- `manual_clips.py`: hand-keyed clips. `-- --setup` creates `shiba_manual.blend`; a plain run bakes and exports every `shiba_*` action in it. Guide: `docs/BLENDER_HAND_ANIMATION.md`.
