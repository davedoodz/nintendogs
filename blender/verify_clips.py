"""Independent reopened-blend and fresh-DAE checks; no asset modifications."""
import math
from pathlib import Path
import sys
import bpy
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
from clip_pipeline import WORK, CLIPS, positions, write_report, BODY_JOINTS, read_clip_channels, matrix_error
from author_clips import root_motion

tier2 = "--tier2" in sys.argv
tier3 = "--tier3" in sys.argv
assert not (tier2 and tier3)
tier = 3 if tier3 else 2 if tier2 else 1
if tier3:
    from tier3_clips import SPECS, check_chains
elif tier2:
    from tier2_clips import SPECS
blend_name = f"shiba_clips_tier{tier}.blend" if tier > 1 else "shiba_clips.blend"
bpy.ops.wm.open_mainfile(filepath=str(WORK / blend_name))
if bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
scene = bpy.context.scene
arm = bpy.data.objects["Armature"]
mesh = bpy.data.objects["Sib_b"]
expected, reports = {}, {}
if tier > 1:
    assert set(bpy.data.actions.keys()) == set(SPECS)
for action in list(bpy.data.actions):
    arm.animation_data.action = action
    end = int(action.frame_range[1])
    frames = sorted({1, end, 1 + end // 4, 1 + end // 2, 1 + 3 * end // 4})
    expected[action.name] = {}
    floor_min = float("inf")
    max_step = 0
    body_limits = {joint: 0 for joint in BODY_JOINTS}
    previous = None
    pad_facing = 1.0
    for frame in range(1, end + 1):
        scene.frame_set(frame)
        points = positions(mesh)
        floor_min = min(floor_min, min(v.z for v in points))
        if frame in frames:
            expected[action.name][frame] = points
        current = [b.rotation_quaternion.copy() for b in arm.pose.bones]
        if tier3 and action.name == 'shiba_paws_up_loop':
            for joint in ['Lhand2', 'Rhand2']:
                deformation = arm.pose.bones[joint].matrix @ arm.data.bones[joint].matrix_local.inverted()
                normal = (deformation.to_3x3() @ Vector((0,-1,0))).normalized()
                pad_facing = min(pad_facing, normal.z)
        for joint in BODY_JOINTS:
            angle = math.degrees(arm.pose.bones[joint].rotation_quaternion.angle)
            body_limits[joint] = max(body_limits[joint], min(angle, 360 - angle))
        if previous:
            max_step = max(max_step, max(math.degrees(a.rotation_difference(b).angle) for a, b in zip(previous, current)))
        previous = current
    reports[action.name] = dict(minimum_world_height=floor_min, max_joint_step_degrees=max_step)
    if tier3 and action.name == 'shiba_paws_up_loop':
        assert pad_facing > .97, ('Pads must face source +Z / camera', pad_facing)
        reports[action.name]['minimum_pad_normal_dot_forward'] = pad_facing
    if tier > 1:
        assert max(body_limits.values()) < 7, (action.name, body_limits)
        reports[action.name]["body_joint_max_degrees"] = body_limits
        frame_count, looping, incoming, outgoing = SPECS[action.name]
        assert tuple(action.frame_range) == (1, frame_count)
        channels = read_clip_channels(CLIPS / (action.name + ".dae"))
        assert all(len(ms) == frame_count for ms in channels.values())
        if tier3 and action.name == 'shiba_paws_up_loop':
            pushes = {}
            for side,index in [('L',18),('R',53)]:
                points = []
                for sample in [0,index]:
                    m = channels['skl_root'][sample].copy()
                    for joint in ['spin',side+'arm1',side+'arm2',side+'hand1',side+'hand2']:
                        m = m @ channels[joint][sample]
                    points.append(m.translation)
                delta = points[1]-points[0]
                assert .018 < delta.z < .022, ('Forward paw push', side, tuple(delta))
                pushes[side] = dict(frame=index+1, source_delta=list(delta))
            reports[action.name]['exported_paw_pushes'] = pushes
        if looping:
            error = max(matrix_error(ms[0], ms[-1]) for ms in channels.values())
            assert error < 2e-5
            reports[action.name]["loop_endpoint_max_error"] = error
        else:
            for endpoint, index, state in [("entry", 0, incoming), ("handoff", -1, outgoing)]:
                if state is None:
                    continue
                reference = read_clip_channels(CLIPS / (state + ".dae"))
                error = max(matrix_error(channels[j][index], reference[j][0]) for j in channels)
                assert error < 2e-5, (action.name, endpoint, error)
                reports[action.name][endpoint] = dict(state=state, max_matrix_error=error)
        if action.name == "shiba_fetch_carry_loop":
            reports[action.name].update(root_motion(channels))
            mouth_error = max(matrix_error(channels["mouth"][0], m) for m in channels["mouth"])
            assert mouth_error < 2e-5
            reports[action.name]["mouth_matrix_range"] = mouth_error
    if action.name in {"shiba_walk_loop", "shiba_run_loop"}:
        reports[action.name].update(root_motion(read_clip_channels(CLIPS / (action.name + ".dae"))))
    assert max(body_limits.values()) < (7 if tier > 1 else 10), (action.name, body_limits)
    assert floor_min > -.003, ("Floor penetration", action.name, floor_min)
    assert max_step < 20, ("Joint motion discontinuity", action.name, max_step)
    print("POSE_CHECK", action.name, reports[action.name], flush=True)
if tier3:
    chains = check_chains({name: read_clip_channels(CLIPS/(name+'.dae')) for name in SPECS})
    print('TIER3_EXPORTED_CHAINS_PASS', chains, flush=True)
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
if tier3:
    reports = dict(clips=reports, chains=chains)
write_report(WORK / (f"tier{tier}_roundtrip_validation.json" if tier > 1 else "clips_roundtrip_validation.json"), reports)
