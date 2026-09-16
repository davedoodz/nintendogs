"""Run with Blender 4.2 LTS --background --factory-startup --python this_file.

Rebuilds the Step 0 clip, working blend, evidence renders and validation report.
Only writes blender/ and mac/Assets/shiba/clips/.
"""
import hashlib
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "mac/Assets/shiba/aSib_b.nsbmd/Sib_b.dae"
OUTPUT = ROOT / "mac/Assets/shiba/clips/shiba_test_tailwag.dae"
WORK = ROOT / "blender"
NS = {"c": "http://www.collada.org/2005/11/COLLADASchema"}
EXPECTED = set("skl_root waist tail1 tail2 tail3 Lleg1 Lleg2 Lfoot1 Lfoot2 Rleg1 Rleg2 Rfoot1 Rfoot2 spin chest Larm1 Larm2 Lhand1 Lhand2 Rarm1 Rarm2 Rhand1 Rhand2 neck head Lear1 Rear1 mouth".split())


def hierarchy(root):
    result = {}

    def walk(node, parent=None):
        if node.get("type") == "JOINT":
            name = node.get("name") or node.get("sid")
            result[name] = parent
            parent = name
        for child in node.findall("c:node", NS):
            walk(child, parent)

    for scene in root.findall(".//c:visual_scene", NS):
        for node in scene.findall("c:node", NS):
            walk(node)
    return result


def mesh_signature(mesh):
    data = {
        "vertices": [list(v.co) for v in mesh.data.vertices],
        "polygons": [list(p.vertices) for p in mesh.data.polygons],
        "uvs": [[list(uv.uv) for uv in layer.data] for layer in mesh.data.uv_layers],
        "weights": [[(g.group, g.weight) for g in v.groups] for v in mesh.data.vertices],
        "groups": [g.name for g in mesh.vertex_groups],
        "materials": [m.name for m in mesh.data.materials],
        "matrix": [list(row) for row in mesh.matrix_world],
        "parent": mesh.parent.name,
    }
    return data


def evaluated_positions(mesh):
    bpy.context.view_layer.update()
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    data = evaluated.to_mesh()
    positions = [evaluated.matrix_world @ v.co for v in data.vertices]
    evaluated.to_mesh_clear()
    return positions


assert bpy.app.version[:2] == (4, 2), bpy.app.version_string
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
assert bpy.ops.wm.collada_import(
    filepath=str(SOURCE), fix_orientation=False, find_chains=False,
    auto_connect=False,
) == {"FINISHED"}
scene = bpy.context.scene
# Force import-time parent/orientation transforms to settle before baselining.
for imported in scene.objects:
    imported.update_tag(refresh={"OBJECT", "DATA", "TIME"})
scene.frame_set(1)
bpy.context.view_layer.update()
armatures = [o for o in scene.objects if o.type == "ARMATURE"]
meshes = [o for o in scene.objects if o.type == "MESH"]
assert len(armatures) == 1 and len(meshes) == 1
armature, mesh = armatures[0], meshes[0]
assert set(armature.data.bones.keys()) == EXPECTED
source_hierarchy = hierarchy(ET.parse(SOURCE).getroot())
import_hierarchy = {b.name: b.parent.name if b.parent else None for b in armature.data.bones}
assert import_hierarchy == source_hierarchy
assert any(m.type == "ARMATURE" and m.object == armature for m in mesh.modifiers)
assert all(v.groups and abs(sum(g.weight for g in v.groups) - 1) < 1e-4 for v in mesh.data.vertices)
rest = evaluated_positions(mesh)
original_signature = mesh_signature(mesh)
unposed = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
rest_error = max((a - b).length for a, b in zip(rest, unposed))
assert rest_error < 1e-4, ("Exploded bind pose", rest_error)

bpy.ops.object.select_all(action="DESELECT")
armature.select_set(True)
bpy.context.view_layer.objects.active = armature
bpy.ops.object.mode_set(mode="POSE")
assert bpy.context.mode == "POSE"
tail = armature.pose.bones["tail1"]
tail.rotation_mode = "XYZ"
# Import defaults keep bone-local Y aligned with the source's vertical Y.
# Rotate around it to swing the tail laterally without changing the bind rig.
tail.rotation_euler.y = math.radians(20)
posed = evaluated_positions(mesh)
distances = [(a - b).length for a, b in zip(rest, posed)]
tail_group_ids = {g.index for g in mesh.vertex_groups if g.name in {"tail1", "tail2", "tail3"}}
tail_vertices = {v.index for v in mesh.data.vertices if any(g.group in tail_group_ids and g.weight > 0 for g in v.groups)}
moved = {i for i, distance in enumerate(distances) if distance > 1e-5}
assert moved and moved <= tail_vertices, ("Unexpected deformation", len(moved), len(tail_vertices))
assert max(distances) < max(mesh.dimensions), "Exploded pose"
tail.rotation_euler.y = 0

scene.render.fps = 30
scene.render.fps_base = 1
scene.frame_start = 1
scene.frame_end = 30
scene.unit_settings.scale_length = 1.0
for frame, degrees in [(1, 0), (8, 20), (15, 0), (22, -20), (30, 0)]:
    tail.rotation_euler.y = math.radians(degrees)
    tail.keyframe_insert(data_path="rotation_euler", index=1, frame=frame, group="tail1")
action = armature.animation_data.action
action.name = "shiba_test_tailwag"
for curve in action.fcurves:
    for key in curve.keyframe_points:
        key.interpolation = "BEZIER"
        key.handle_left_type = key.handle_right_type = "AUTO_CLAMPED"
assert len(bpy.data.actions) == 1 and tuple(action.frame_range) == (1, 30)
scene.frame_set(1)
bpy.context.view_layer.update()
assert mesh_signature(mesh) == original_signature, {key: (value, mesh_signature(mesh)[key]) for key, value in original_signature.items() if value != mesh_signature(mesh)[key]}
bpy.ops.object.mode_set(mode="OBJECT")
mesh.select_set(True)
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
export_settings = dict(
    selected=True, include_animations=True, include_all_actions=False,
    export_animation_type_selection="sample", sampling_rate=1,
    keep_keyframes=False, keep_smooth_curves=False,
    export_object_transformation_type_selection="matrix",
    export_animation_transformation_type_selection="matrix",
    export_global_up_selection="Y", export_global_forward_selection="-Z",
    apply_global_orientation=True, apply_modifiers=False, triangulate=False,
    use_texture_copies=False,
)
assert bpy.ops.wm.collada_export(filepath=str(OUTPUT), **export_settings) == {"FINISHED"}
# Native exporter emits absolute Windows texture paths with copies disabled.
# Make only image references portable; retain all native geometry/animation XML.
export_text = OUTPUT.read_text(encoding="utf-8")
for image_node in ET.fromstring(export_text).findall("c:library_images/c:image/c:init_from", NS):
    texture_name = image_node.text.replace("\\", "/").rsplit("/", 1)[-1]
    assert (SOURCE.parent / texture_name).is_file()
    export_text = export_text.replace(image_node.text, "../aSib_b.nsbmd/" + texture_name)
OUTPUT.write_text(export_text, encoding="utf-8")
export_root = ET.parse(OUTPUT).getroot()
assert hierarchy(export_root) == source_hierarchy
channels = export_root.findall(".//c:channel", NS)
assert channels, "No animation exported"
nodes_by_id = {n.get("id"): n for n in export_root.findall(".//c:node", NS)}
tail_channels = [c for c in channels if nodes_by_id.get(c.get("target").split("/")[0]) is not None
                 and nodes_by_id[c.get("target").split("/")[0]].get("name") == "tail1"]
assert tail_channels, "No tail1 channel"
samplers = {s.get("id"): s for s in export_root.findall(".//c:sampler", NS)}
sources = {s.get("id"): s for s in export_root.findall(".//c:source", NS)}
for channel in tail_channels:
    sampler = samplers[channel.get("source")[1:]]
    inputs = {i.get("semantic"): sources[i.get("source")[1:]] for i in sampler.findall("c:input", NS)}
    times = [float(x) for x in inputs["INPUT"].find("c:float_array", NS).text.split()]
    matrices = [float(x) for x in inputs["OUTPUT"].find("c:float_array", NS).text.split()]
    assert len(times) == 30 and len(matrices) == 30 * 16
    assert all(abs((b - a) - 1 / 30) < 1e-5 for a, b in zip(times, times[1:]))
    assert max(abs(a - b) for a, b in zip(matrices[:16], matrices[7*16:8*16])) > 0.01
assert mesh_signature(mesh) == original_signature

# Portable working file: relative texture paths resolve on the other machine.
for image in bpy.data.images:
    if image.source == "FILE" and image.filepath:
        image.filepath = "//../mac/Assets/shiba/aSib_b.nsbmd/" + Path(bpy.path.abspath(image.filepath)).name
armature.show_in_front = True
mesh.select_set(False)
armature.data.bones.active = armature.data.bones["tail1"]
for bone in armature.data.bones:
    bone.select = bone.name == "tail1"
bpy.ops.object.mode_set(mode="POSE")
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(WORK / "shiba_test_tailwag.blend"))

report = {
    "result": "GO: Blender import, Pose Mode deformation and sampled export passed; SceneKit playback pending Mac validation",
    "blender": bpy.app.version_string,
    "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    "bones": len(import_hierarchy), "hierarchy_matches_source": True,
    "source_hierarchy": source_hierarchy,
    "contract_diagram_discrepancies": {"spin": "source parent skl_root; diagram waist", "Larm1": "source parent spin; diagram chest", "Rarm1": "source parent spin; diagram chest"},
    "vertices": len(mesh.data.vertices), "rest_pose_max_error": rest_error,
    "pose_mode_test": {"bone": "tail1", "rotation_degrees": 20, "axis": "local Y", "moved_vertices": len(moved), "tail_weighted_vertices": len(tail_vertices), "non_tail_vertices_moved": len(moved - tail_vertices), "max_displacement": max(distances)},
    "mesh_uv_weights_materials_transforms_unchanged": True,
    "frame_range": [1, 30], "fps": 30, "actions": [action.name],
    "tail_channel_samples": len(times), "sample_time_range_seconds": [times[0], times[-1]],
    "export_settings": export_settings,
    "export_up_axis": export_root.find("c:asset/c:up_axis", NS).text,
    "exporter_note": "Blender 4.2 writes Z_UP metadata even with Y-up/-Z-forward export selectors. Apply Global Orientation enabled for consistent exported rest and animation matrices; no transforms applied to the working model. Only image paths normalized to relative references after export.",
    "export_channels": [c.get("target") for c in channels],
}
(WORK / "step0_validation.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print("STEP0_RESULT", json.dumps(report))

# Temporary render objects are created after saving and never enter the clip/blend.
bpy.ops.object.mode_set(mode="OBJECT")
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16
scene.render.resolution_x = 800
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.22, 0.22, 0.22, 1)
scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.7
center = sum(rest, Vector()) / len(rest)
up = (armature.matrix_world.to_3x3() @ Vector((0, 1, 0))).normalized()
side = (armature.matrix_world.to_3x3() @ Vector((1, 0, 0))).normalized()
forward = (armature.matrix_world.to_3x3() @ Vector((0, 0, 1))).normalized()
bpy.ops.object.camera_add(location=center + side * 8 - forward * 9 + up * 6)
camera = bpy.context.object
camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 7
scene.camera = camera
bpy.ops.object.light_add(type="AREA", location=center + side * 3 - forward * 4 + up * 7)
light = bpy.context.object
light.data.energy = 1600
light.data.shape = "DISK"
light.data.size = 5
light.rotation_euler = (center - light.location).to_track_quat("-Z", "Y").to_euler()
for frame in [8, 22]:
    scene.frame_set(frame)
    scene.render.filepath = str(WORK / f"step0_tailwag_frame{frame:02d}.png")
    bpy.ops.render.render(write_still=True)
