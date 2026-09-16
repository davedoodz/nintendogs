# Revised seam test: tail2 horizontal yaw

The test is now 30 frames at 30 fps, with `tail2` at 0, +20, 0, -20 and 0
degrees on frames 1, 8, 15, 22 and 30. `tail1` stays exactly at rest and has no
animation channel. Only the 42 vertices weighted to `tail2`/`tail3` move.
Vertical displacement is below 0.000001 units; yaw was checked in both the
Blender pose and the delivered source-coordinate animation matrices.

All 28 bone names and parents, source mesh, UVs, rigid skin weights, inverse bind
matrices and materials are preserved. The contract diagram now agrees with the
source. Mac confirmed the earlier clip played; the revised seam test awaits its
new Mac capture.

## Export and coordinate conversion

`step0_tailwag.py` uses Blender 4.2.23 and the same native export settings as the
first test. `clip_pipeline.py` then converts native sampled matrices back into
the original source joint bases. This is necessary because Blender changes bone
orientations during import and rotates their bases during export; copying those
absolute matrices onto the source rig turned the previous yaw into pitch and
also changed the tail1 rest transform.

For each bone, source posed global = Blender posed global × inverse(Blender rest)
× source rest. Parent-relative matrices are then calculated for the channels.
The delivered DAE retains the source's geometry, controller and static rig, uses
explicit Y_UP metadata, and references textures relative to `../aSib_b.nsbmd/`.
There is no mesh alteration, weight edit, re-parenting or Mac code change.

Native intermediate exports are reproducible under ignored `blender/native_exports/`.
The conversion verifies every native sample against the authored Blender pose
(maximum matrix error below 0.000001 for this test). It does not invent or
replace the authored motion. See `step0_validation.json` for exact arguments
and measurements, and the two PNGs for opposite wag extremes.

From the repository root:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 4.2\blender.exe' --background --factory-startup --python-exit-code 1 --python blender/step0_tailwag.py
```

`shiba_test_tailwag.blend` opens in Pose Mode with `tail2` selected.
