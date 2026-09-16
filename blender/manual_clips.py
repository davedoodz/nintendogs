"""Hand-keyed clips: create the working file, then bake + export every action in it.

Run in Blender 4.2 LTS from the repository root (Windows):

  blender.exe --background --factory-startup --python-exit-code 1 --python blender/manual_clips.py -- --setup
      Creates blender/shiba_manual.blend with the imported coat-B rig. Open it in
      the Blender GUI and key poses in Pose Mode. See docs/BLENDER_HAND_ANIMATION.md.

  blender.exe --background --factory-startup --python-exit-code 1 --python blender/manual_clips.py
      Exports every action named shiba_* from shiba_manual.blend to
      mac/Assets/shiba/clips/<action>.dae through the contract pipeline
      (sampled every frame, source-basis conversion, joint limits, loop closure).
      Add -- --only shiba_call_stun to export a single action.

Actions named shiba_layer_* export only the bones that were keyed (tail-only,
mouth-only overlays). Everything else exports all 28 joints.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from clip_pipeline import CLIPS, WORK, Rig, matrix_error, write_report  # noqa: E402

BLEND = WORK / "shiba_manual.blend"
BODY_LIMIT_DEGREES = 10  # tail1, neck, Lleg1/Rleg1, Larm1/Rarm1 (rigid skinning seam rule)


def keyed_bones(action):
    bones = set()
    for curve in action.fcurves:
        path = curve.data_path
        if path.startswith('pose.bones["'):
            bones.add(path.split('"')[1])
    return bones


def bake(rig, action, name, only=None):
    """Sample the hand-keyed action every frame and re-key it as linear quaternion
    keys (plus root location), exactly as the procedural clips are keyed."""
    rig.arm.animation_data_create()
    rig.arm.animation_data.action = action
    start, end = map(int, action.frame_range)
    frames = end - start + 1
    assert frames >= 2, (name, "needs at least two frames")
    samples = []
    for frame in range(start, end + 1):
        rig.scene.frame_set(frame)
        samples.append({b.name: b.matrix_basis.copy() for b in rig.arm.pose.bones})
    baked = bpy.data.actions.new(name + "_baked")
    rig.arm.animation_data.action = baked
    rig.scene.frame_start, rig.scene.frame_end = 1, frames
    joints = [b.name for b in rig.arm.pose.bones if only is None or b.name in only]
    previous = {}
    warnings = set()
    for index, pose in enumerate(samples, start=1):
        for joint in joints:
            bone = rig.arm.pose.bones[joint]
            basis = pose[joint]
            translation = basis.to_translation()
            if joint != "skl_root" and translation.length > 1e-4:
                warnings.add(f"{joint} was moved (translated); only rotation is kept")
            if (basis.to_scale() - Vector((1, 1, 1))).length > 1e-4:
                warnings.add(f"{joint} was scaled; scale is discarded")
            rotation = basis.to_quaternion()
            if joint in previous and previous[joint].dot(rotation) < 0:
                rotation.negate()
            previous[joint] = rotation
            bone.rotation_mode = "QUATERNION"
            bone.rotation_quaternion = rotation
            bone.scale = (1, 1, 1)
            bone.location = translation if joint == "skl_root" else Vector((0, 0, 0))
            bone.keyframe_insert("rotation_quaternion", frame=index, group=joint)
            if joint == "skl_root":
                bone.keyframe_insert("location", frame=index, group=joint)
    for curve in baked.fcurves:
        for key in curve.keyframe_points:
            key.interpolation = "LINEAR"
    rig.actions[name] = baked
    rig.scene.frame_set(1)
    return frames, sorted(warnings)


def build_manual(only=None):
    assert BLEND.exists(), f"{BLEND} is missing; run with -- --setup first"
    rig = Rig(blend=BLEND)
    names = sorted(a.name for a in bpy.data.actions
                   if a.name.startswith("shiba_") and not a.name.endswith("_baked"))
    if only:
        assert only in names, (only, names)
        names = [only]
    assert names, "no actions named shiba_* in shiba_manual.blend"
    reports = {}
    for name in names:
        action = bpy.data.actions[name]
        layer = name.startswith("shiba_layer_")
        subset = keyed_bones(action) if layer else None
        assert not layer or subset, (name, "layer clip has no keyed bones")
        frames, warnings = bake(rig, action, name, only=subset)
        report, samples = rig.export(name, full_pose=not layer, joint_limit=BODY_LIMIT_DEGREES)
        report["warnings"] = warnings
        report["layer_bones"] = sorted(subset) if layer else None
        if name.endswith("_loop"):
            error = max(matrix_error(ms[0], ms[-1]) for ms in samples.values())
            report["loop_endpoint_max_error"] = error
            assert error < 1e-3, (name, "loop does not close: copy frame 1's pose onto the last frame", error)
        reports[name] = report
        print(f"exported {name}: {frames} frames"
              + (f", layer bones {sorted(subset)}" if layer else "")
              + ("; WARNINGS: " + "; ".join(warnings) if warnings else ""))
    write_report(WORK / "manual_validation.json", reports)
    print(f"wrote {len(reports)} clip(s) to {CLIPS}")


def setup():
    rig = Rig()
    rig.save(BLEND, selected_bone="head")
    print(f"created {BLEND}: open it in Blender, switch to Pose Mode, and start keying")


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--setup" in args:
        setup()
    else:
        only = args[args.index("--only") + 1] if "--only" in args else None
        build_manual(only)
