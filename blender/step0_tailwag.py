"""Rebuild the 30-frame tail2 horizontal wag; run with Blender 4.2 LTS."""
from pathlib import Path
import sys
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
from clip_pipeline import Rig, WORK, positions, write_report, matrix_error

rig = Rig()


def pose(t):
    frame = 1 + t * 29
    keys = [(1, 0), (8, 20), (15, 0), (22, -20), (30, 0)]
    for (a, av), (b, bv) in zip(keys, keys[1:]):
        if a <= frame <= b:
            u = (frame - a) / (b - a)
            u = u * u * (3 - 2 * u)
            return {"tail2": (0, av + (bv - av) * u, 0)}
    return {}


action = rig.action("shiba_test_tailwag", 30, pose, keyed_bones=["tail2"])
rig.scene.frame_set(8)
posed = positions(rig.mesh)
distances = [(a - b).length for a, b in zip(rig.rest_points, posed)]
up = rig.arm.matrix_world.to_3x3() @ Vector((0, 1, 0))
height_error = max(abs((a - b).dot(up)) for a, b in zip(rig.rest_points, posed))
assert height_error < 1e-5, ("Wag must be horizontal", height_error)
tail1_error = matrix_error(rig.arm.pose.bones["tail1"].matrix, rig.rest["tail1"])
assert tail1_error < 1e-6
report, channels = rig.export("shiba_test_tailwag", full_pose=False)
assert set(channels) == {"tail2"}
vertical = Vector((0, 1, 0))
yaw_error = max(((m.to_3x3() @ vertical) - vertical).length for m in channels["tail2"])
assert yaw_error < 1e-5, ("Source channel is not yaw", yaw_error)
report.update(result="tail2 +/-20 degree horizontal yaw; tail1 stationary; Mac seam recapture pending",
              pose_mode_test={"bone": "tail2", "yaw_extremes_degrees": [-20, 20],
                              "tail1_max_matrix_error": tail1_error,
                              "moved_vertices": sum(d > 1e-5 for d in distances),
                              "max_vertical_vertex_motion": height_error,
                              "exported_yaw_axis_error": yaw_error})
rig.save(WORK / "shiba_test_tailwag.blend")
write_report(WORK / "step0_validation.json", report)
for frame in [8, 22]:
    rig.render(WORK / f"step0_tailwag_frame{frame:02d}.png", frame)
print("STEP0_PASS", report)
