# Step 0: Blender GO; Mac playback validation pending

Blender 4.2.23 LTS imported all 28 named bones and the 1,140-vertex coat-B mesh.
In Pose Mode, rotating `tail1` 20 degrees about local Y moved all 58 tail-weighted
vertices and no other vertices. The rest-pose error was below 0.000001 units;
mesh data, UVs, skin weights, material names, parenting and object transforms
were unchanged by authoring.

`shiba_test_tailwag.blend` opens in Pose Mode with `tail1` selected. Its single
action runs from frame 1 through 30 at 30 fps, keyed at 1, 8, 15, 22 and 30
(neutral, +20 degrees, neutral, -20 degrees, neutral). The exported clip is
`../mac/Assets/shiba/clips/shiba_test_tailwag.dae`. It contains 30 sampled matrix
keys on the node named `tail1`, with all 28 joint names and source parents intact.
Two PNGs show the opposing wag extremes. Machine-readable checks and the exact
export arguments are in `step0_validation.json`.

A fresh Blender process reopened the saved blend in Pose Mode with the action
and textures intact. Reimporting the exported DAE also retained 28 bones and
1,140 vertices, with animation moving only the same 58 tail vertices.

## Handoff observations

- The actual source parents are `spin` under `skl_root`, and `Larm1`/`Rarm1`
  under `spin`. These differ from the contract diagram. The source hierarchy
  was preserved without re-parenting.
- Blender 4.2's native exporter writes `Z_UP` asset metadata even when its
  global orientation selectors are Y up / -Z forward. The clip retains the
  native export output; Apply Global Orientation is enabled in the exporter to
  keep exported rest and animation matrices consistent. No object transforms
  are applied in the working blend. Mac should check
  orientation along with animation retargeting on the original coat-B rig.
  This behavior is hardcoded in Blender's
  [DocumentExporter.cpp](https://raw.githubusercontent.com/blender/blender/blender-v4.2-release/source/blender/io/collada/DocumentExporter.cpp).
- Image references are normalized after export from absolute Windows paths to
  `../aSib_b.nsbmd/` paths so the existing textures resolve on both machines.
- SceneKit playback and attaching the clip to the original model require the
  Mac-side test specified in the contract. Blender success does not establish
  that result.

No changes were made outside `blender/` and `mac/Assets/shiba/clips/`.

## Rebuild on Windows

From the repository root, run:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 4.2\blender.exe' --background --factory-startup --python-exit-code 1 --python blender/step0_tailwag.py
```

The script uses Blender's native Collada import/export and asserts rig identity,
deformation locality, unchanged source mesh data, and sampled animation output.
It refreshes import-time dependency state before taking its baseline; Blender's
import otherwise leaves the mesh parent/orientation matrix stale initially.
