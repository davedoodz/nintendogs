"""Independent reopened-blend and fresh-DAE checks; no asset modifications."""
import math
from pathlib import Path
import sys
import bpy
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
from clip_pipeline import WORK, CLIPS, positions, write_report

bpy.ops.wm.open_mainfile(filepath=str(WORK / "shiba_clips.blend"))
if bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
scene = bpy.context.scene
arm = bpy.data.objects["Armature"]
mesh = bpy.data.objects["Sib_b"]
expected, reports = {}, {}
for action in list(bpy.data.actions):
    arm.animation_data.action = action
    end = int(action.frame_range[1])
    frames = sorted({1, end, 1 + end // 4, 1 + end // 2, 1 + 3 * end // 4})
    expected[action.name] = {}
    floor_min = float("inf")
    max_step = 0
    previous = None
    for frame in range(1, end + 1):
        scene.frame_set(frame)
        points = positions(mesh)
        floor_min = min(floor_min, min(v.z for v in points))
        if frame in frames:
            expected[action.name][frame] = points
        current = [b.rotation_quaternion.copy() for b in arm.pose.bones]
        if previous:
            max_step = max(max_step, max(math.degrees(a.rotation_difference(b).angle) for a, b in zip(previous, current)))
        previous = current
    reports[action.name] = dict(minimum_world_height=floor_min, max_joint_step_degrees=max_step)
    assert floor_min > -.003, ("Floor penetration", action.name, floor_min)
    assert max_step < 20, ("Joint motion discontinuity", action.name, max_step)
    print("POSE_CHECK", action.name, reports[action.name], flush=True)
for name, frames in expected.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 30
    bpy.ops.wm.collada_import(filepath=str(CLIPS / (name + ".dae")), fix_orientation=False, find_chains=False, auto_connect=False)
    for obj in scene.objects:
        obj.update_tag(refresh={"OBJECT", "DATA", "TIME"})
    arm = next(o for o in scene.objects if o.type == "ARMATURE")
    mesh = next(o for o in scene.objects if o.type == "MESH")
    assert len(arm.data.bones) == 28 and len(mesh.data.vertices) == 1140
    error = 0
    for frame, before in frames.items():
        scene.frame_set(frame)
        after = positions(mesh)
        error = max(error, max((a - b).length for a, b in zip(before, after)))
    reports[name]["fresh_dae_max_vertex_error"] = error
    assert error < .005, ("Reimport pose mismatch", name, error)
    print("REIMPORT_PASS", name, error, flush=True)
write_report(WORK / "clips_roundtrip_validation.json", reports)
