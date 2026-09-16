"""Native Blender 4.2 samples rebased to the source joint coordinate systems.

SceneKit copies absolute local matrices by name. Import/export changes the bone
bases, so native channels must be expressed in the original bases before copying.
Source geometry, controllers, weights, UVs and hierarchy are retained verbatim.
"""
import copy
import hashlib
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET
import bpy
from bpy_extras.io_utils import axis_conversion
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "blender"
CLIPS = ROOT / "mac/Assets/shiba/clips"
SOURCE = ROOT / "mac/Assets/shiba/aSib_b.nsbmd/Sib_b.dae"
NS = {"c": "http://www.collada.org/2005/11/COLLADASchema"}
TAG = "{" + NS["c"] + "}"
ET.register_namespace("", NS["c"])
BODY_JOINTS = ("tail1", "neck", "Lleg1", "Rleg1", "Larm1", "Rarm1")
EXPORT_SETTINGS = dict(
    selected=True, include_animations=True, include_all_actions=False,
    export_animation_type_selection="sample", sampling_rate=1,
    keep_keyframes=False, keep_smooth_curves=False,
    export_object_transformation_type_selection="matrix",
    export_animation_transformation_type_selection="matrix",
    export_global_up_selection="Y", export_global_forward_selection="-Z",
    apply_global_orientation=True, apply_modifiers=False, triangulate=False,
    use_texture_copies=False,
)


def matrix(text):
    values = [float(x) for x in text.split()]
    return Matrix([values[i:i + 4] for i in range(0, 16, 4)])


def floats(mat):
    return [value for row in mat for value in row]


def matrix_error(a, b):
    return max(abs(x - y) for x, y in zip(floats(a), floats(b)))


def source_rig(root):
    nodes, parents, globals_ = {}, {}, {}
    def walk(node, parent=None):
        if node.get("type") == "JOINT":
            name = node.get("name")
            nodes[name], parents[name] = node, parent
            local = matrix(node.find("c:matrix", NS).text)
            globals_[name] = globals_[parent] @ local if parent else local
            parent = name
        for child in node.findall("c:node", NS):
            walk(child, parent)
    for scene in root.findall(".//c:visual_scene", NS):
        for node in scene.findall("c:node", NS):
            walk(node)
    return nodes, parents, globals_


def positions(mesh):
    bpy.context.view_layer.update()
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    data = evaluated.to_mesh()
    points = [evaluated.matrix_world @ v.co for v in data.vertices]
    evaluated.to_mesh_clear()
    return points


def read_clip_channels(path):
    """Read delivered DAE matrices, including per-frame timing validation."""
    root = ET.parse(path).getroot()
    nodes, _, _ = source_rig(root)
    names = {node.get("id"): name for name, node in nodes.items()}
    sources = {n.get("id"): n for n in root.findall(".//c:source", NS)}
    samplers = {n.get("id"): n for n in root.findall(".//c:sampler", NS)}
    result = {}
    for channel in root.findall(".//c:channel", NS):
        target, transform = channel.get("target").split("/")
        assert transform == "transform" and target in names
        inputs = {i.get("semantic"): sources[i.get("source")[1:]]
                  for i in samplers[channel.get("source")[1:]].findall("c:input", NS)}
        times = [float(v) for v in inputs["INPUT"].find("c:float_array", NS).text.split()]
        values = inputs["OUTPUT"].find("c:float_array", NS).text.split()
        assert len(values) == 16 * len(times)
        assert all(abs(b - a - 1 / 30) < 1e-5 for a, b in zip(times, times[1:]))
        assert abs(times[0] - 1 / 30) < 1e-5
        result[names[target]] = [matrix(" ".join(values[i:i+16])) for i in range(0, len(values), 16)]
    assert len(result) == 28
    return result


class Rig:
    def __init__(self, blend=None):
        """Fresh DAE import by default; `blend` opens a saved working file instead
        (hand-keyed actions in `shiba_manual.blend`). Everything after the load is
        identical, so exports from either path go through the same checks."""
        assert bpy.app.version[:2] == (4, 2)
        self.source = ET.parse(SOURCE).getroot()
        self.nodes, self.parents, self.source_rest = source_rig(self.source)
        if blend is None:
            bpy.ops.wm.read_factory_settings(use_empty=True)
            bpy.ops.wm.collada_import(filepath=str(SOURCE), fix_orientation=False,
                                     find_chains=False, auto_connect=False)
        else:
            bpy.ops.wm.open_mainfile(filepath=str(blend))
            if bpy.context.object and bpy.context.object.mode != "OBJECT":
                bpy.ops.object.mode_set(mode="OBJECT")
        self.scene = bpy.context.scene
        for obj in self.scene.objects:
            obj.update_tag(refresh={"OBJECT", "DATA", "TIME"})
        self.scene.frame_set(1)
        bpy.context.view_layer.update()
        self.arm = next(o for o in self.scene.objects if o.type == "ARMATURE")
        self.mesh = next(o for o in self.scene.objects if o.type == "MESH")
        self.rest = {b.name: b.matrix_local.copy() for b in self.arm.data.bones}
        assert len(self.rest) == 28 and set(self.rest) == set(self.nodes)
        assert self.parents == {b.name: b.parent.name if b.parent else None for b in self.arm.data.bones}
        assert all(len(v.groups) == 1 and abs(v.groups[0].weight - 1) < 1e-6 for v in self.mesh.data.vertices)
        self.signature = self.mesh_signature()
        self.rest_points = positions(self.mesh)
        self.scene.render.fps, self.scene.render.fps_base = 30, 1
        self.scene.unit_settings.scale_length = 1
        self.arm.show_in_front = True
        self.actions = {}

    def mesh_signature(self):
        return dict(vertices=[list(v.co) for v in self.mesh.data.vertices],
                    polygons=[list(p.vertices) for p in self.mesh.data.polygons],
                    uvs=[[list(v.uv) for v in u.data] for u in self.mesh.data.uv_layers],
                    weights=[[(g.group, g.weight) for g in v.groups] for v in self.mesh.data.vertices],
                    materials=[m.name for m in self.mesh.data.materials],
                    parent=self.mesh.parent.name, object_matrix=floats(self.mesh.matrix_world))

    def set_pose(self, pose):
        # Pitch X, yaw Y, roll Z in source coordinates; parents carry descendants.
        for bone in self.arm.pose.bones:
            bone.rotation_mode = "QUATERNION"
            pitch, yaw, roll = pose.get(bone.name, (0, 0, 0))
            rotation = (Quaternion((0, 1, 0), math.radians(yaw)) @
                        Quaternion((1, 0, 0), math.radians(pitch)) @
                        Quaternion((0, 0, 1), math.radians(roll)))
            basis = self.rest[bone.name].to_quaternion()
            bone.rotation_quaternion = basis.inverted() @ rotation @ basis
            bone.location, bone.scale = (0, 0, 0), (1, 1, 1)
        self.arm.pose.bones["skl_root"].location = self.rest["skl_root"].to_3x3().inverted() @ Vector(pose.get("root_location", (0, 0, 0)))
        bpy.context.view_layer.update()

    def action(self, name, frames, pose_function, keyed_bones=None, floor_contact=False):
        self.arm.animation_data_create()
        action = bpy.data.actions.new(name)
        self.arm.animation_data.action = action
        self.scene.frame_start, self.scene.frame_end = 1, frames
        self.set_pose({})
        up = self.arm.matrix_world.to_3x3() @ Vector((0, 1, 0))
        floor = min(v.dot(up) for v in self.rest_points)
        previous_rotations = {}
        for frame in range(1, frames + 1):
            self.set_pose(pose_function((frame - 1) / (frames - 1)))
            if floor_contact:
                correction = max(0, floor - min(v.dot(up) for v in positions(self.mesh)))
                self.arm.pose.bones["skl_root"].location += self.rest["skl_root"].to_3x3().inverted() @ Vector((0, correction, 0))
                bpy.context.view_layer.update()
            for joint in list(keyed_bones or self.nodes):
                bone = self.arm.pose.bones[joint]
                # q and -q describe the same pose; keep one hemisphere so
                # component interpolation cannot spin when a joint crosses 180°.
                rotation = bone.rotation_quaternion.copy()
                if joint in previous_rotations and previous_rotations[joint].dot(rotation) < 0:
                    rotation.negate()
                    bone.rotation_quaternion = rotation
                previous_rotations[joint] = rotation
                bone.keyframe_insert("rotation_quaternion", frame=frame, group=joint)
                if joint == "skl_root":
                    bone.keyframe_insert("location", frame=frame, group=joint)
        for curve in action.fcurves:
            for key in curve.keyframe_points:
                key.interpolation = "LINEAR"
        action.use_fake_user = True
        self.actions[name] = action
        self.scene.frame_set(1)
        return action

    def activate(self, action):
        self.arm.animation_data.action = action
        self.scene.frame_start, self.scene.frame_end = map(int, action.frame_range)
        self.scene.frame_set(self.scene.frame_start)

    def save(self, path, selected_bone="tail2"):
        if bpy.context.object and bpy.context.object.mode != "OBJECT":
            bpy.ops.object.mode_set(mode="OBJECT")
        bpy.ops.object.select_all(action="DESELECT")
        self.arm.select_set(True)
        bpy.context.view_layer.objects.active = self.arm
        for bone in self.arm.data.bones:
            bone.select = bone.name == selected_bone
        self.arm.data.bones.active = self.arm.data.bones[selected_bone]
        bpy.ops.object.mode_set(mode="POSE")
        for image in bpy.data.images:
            if image.source == "FILE" and image.filepath:
                image.filepath = "//../mac/Assets/shiba/aSib_b.nsbmd/" + Path(bpy.path.abspath(image.filepath)).name
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(path))
        bpy.ops.object.mode_set(mode="OBJECT")

    def export(self, name, full_pose=True, joint_limit=10):
        # Source posed global = sampled Blender global @ inverse(Blender rest)
        #                       @ source rest. Recompute parent-relative matrices.
        self.activate(self.actions[name])
        start, end = self.scene.frame_start, self.scene.frame_end
        expected, limits = [], {name: 0 for name in BODY_JOINTS}
        for frame in range(start, end + 1):
            self.scene.frame_set(frame)
            expected.append({b.name: b.matrix.copy() for b in self.arm.pose.bones})
            for joint in limits:
                angle = math.degrees(self.arm.pose.bones[joint].rotation_quaternion.angle)
                limits[joint] = max(limits[joint], min(angle, 360 - angle))
        assert max(limits.values()) < joint_limit, limits
        self.scene.frame_set(1)
        assert self.mesh_signature() == self.signature
        bpy.ops.object.select_all(action="DESELECT")
        self.arm.select_set(True)
        self.mesh.select_set(True)
        bpy.context.view_layer.objects.active = self.arm
        CLIPS.mkdir(exist_ok=True)
        native_dir = WORK / "native_exports"
        native_dir.mkdir(exist_ok=True)
        native_path = native_dir / (name + ".dae")
        settings = dict(EXPORT_SETTINGS)
        if full_pose:
            settings["keep_flat_curves"] = True  # Retain holds and state resets.
        assert bpy.ops.wm.collada_export(filepath=str(native_path), **settings) == {"FINISHED"}
        native = ET.parse(native_path).getroot()
        native_nodes, native_parents, _ = source_rig(native)
        assert native_parents == self.parents
        id_names = {n.get("id"): joint for joint, n in native_nodes.items()}
        sources = {n.get("id"): n for n in native.findall(".//c:source", NS)}
        samplers = {n.get("id"): n for n in native.findall(".//c:sampler", NS)}
        animations, sample_times = {}, None
        for channel in native.findall(".//c:channel", NS):
            joint = id_names.get(channel.get("target").split("/")[0])
            if joint is None:
                continue
            sampler = samplers[channel.get("source")[1:]]
            inputs = {i.get("semantic"): sources[i.get("source")[1:]] for i in sampler.findall("c:input", NS)}
            times = [float(v) for v in inputs["INPUT"].find("c:float_array", NS).text.split()]
            values = inputs["OUTPUT"].find("c:float_array", NS).text.split()
            assert len(times) == end - start + 1 and len(values) == len(times) * 16
            assert all(abs(b - a - 1 / 30) < 1e-5 for a, b in zip(times, times[1:]))
            animations[joint] = [matrix(" ".join(values[i:i + 16])) for i in range(0, len(values), 16)]
            sample_times = times
        assert animations
        if full_pose:
            assert set(animations) == set(self.nodes), (name, set(self.nodes) - set(animations))
        orientation = axis_conversion(to_forward="-Z", to_up="Y").to_4x4()
        inverse_orientation = orientation.inverted()
        native_locals = {k: matrix(v.find("c:matrix", NS).text) for k, v in native_nodes.items()}
        corrected = {key: [] for key in animations}
        max_sample_error = 0
        for index in range(len(sample_times)):
            blender_global, source_global = {}, {}
            for joint in self.nodes:
                exported = animations[joint][index] if joint in animations else native_locals[joint]
                local = inverse_orientation @ exported @ orientation
                parent = self.parents[joint]
                blender_global[joint] = blender_global[parent] @ local if parent else local
                max_sample_error = max(max_sample_error, matrix_error(blender_global[joint], expected[index][joint]))
                source_global[joint] = blender_global[joint] @ self.rest[joint].inverted() @ self.source_rest[joint]
                if joint in corrected:
                    corrected[joint].append(source_global[parent].inverted() @ source_global[joint] if parent else source_global[joint])
        assert max_sample_error < 2e-4, ("Native sample conversion mismatch", name, max_sample_error)
        result = copy.deepcopy(self.source)
        library = ET.Element(TAG + "library_animations")
        result.insert(list(result).index(result.find("c:library_visual_scenes", NS)), library)
        for joint, matrices in corrected.items():
            ident = name + "_" + joint
            animation = ET.SubElement(library, TAG + "animation", id=ident, name=ident)
            for suffix, values, stride, param_name, param_type in [
                ("input", sample_times, 1, "TIME", "float"),
                ("output", [x for mat in matrices for x in floats(mat)], 16, "TRANSFORM", "float4x4"),
            ]:
                source = ET.SubElement(animation, TAG + "source", id=ident + "_" + suffix)
                array_id = ident + "_" + suffix + "_array"
                array = ET.SubElement(source, TAG + "float_array", id=array_id, count=str(len(values)))
                array.text = " ".join(format(v, ".9g") for v in values)
                common = ET.SubElement(source, TAG + "technique_common")
                accessor = ET.SubElement(common, TAG + "accessor", source="#" + array_id, count=str(len(sample_times)), stride=str(stride))
                ET.SubElement(accessor, TAG + "param", name=param_name, type=param_type)
            source = ET.SubElement(animation, TAG + "source", id=ident + "_interpolation")
            array = ET.SubElement(source, TAG + "Name_array", id=ident + "_interpolation_array", count=str(len(sample_times)))
            array.text = " ".join(["LINEAR"] * len(sample_times))
            accessor = ET.SubElement(ET.SubElement(source, TAG + "technique_common"), TAG + "accessor", source="#" + ident + "_interpolation_array", count=str(len(sample_times)), stride="1")
            ET.SubElement(accessor, TAG + "param", name="INTERPOLATION", type="name")
            sampler = ET.SubElement(animation, TAG + "sampler", id=ident + "_sampler")
            for semantic in ["INPUT", "OUTPUT", "INTERPOLATION"]:
                ET.SubElement(sampler, TAG + "input", semantic=semantic, source="#" + ident + "_" + semantic.lower())
            ET.SubElement(animation, TAG + "channel", source="#" + ident + "_sampler", target=self.nodes[joint].get("id") + "/transform")
        asset = result.find("c:asset", NS)
        if asset is None:
            asset = ET.Element(TAG + "asset")
            result.insert(0, asset)
        unit = asset.find("c:unit", NS)
        if unit is None:
            unit = ET.SubElement(asset, TAG + "unit")
        unit.set("name", "meter")
        unit.set("meter", "1")
        up = asset.find("c:up_axis", NS)
        if up is None:
            up = ET.SubElement(asset, TAG + "up_axis")
        up.text = "Y_UP"
        for image in result.findall("c:library_images/c:image/c:init_from", NS):
            image.text = "../aSib_b.nsbmd/" + image.text.rsplit("/", 1)[-1]
        for tag in ["library_geometries", "library_controllers", "library_visual_scenes", "library_materials", "library_effects"]:
            assert ET.tostring(result.find("c:" + tag, NS)) == ET.tostring(self.source.find("c:" + tag, NS)), tag
        ET.ElementTree(result).write(CLIPS / (name + ".dae"), encoding="utf-8", xml_declaration=True)
        self.scene.frame_set(1)
        return dict(name=name, frames=[start, end], fps=30, bone_count=28,
                    channels=list(corrected), body_joint_max_degrees=limits,
                    native_sample_max_matrix_error=max_sample_error,
                    source_geometry_skin_bind_hierarchy_preserved=True,
                    mesh_data_unchanged=self.mesh_signature() == self.signature,
                    export_settings=settings, final_up_axis="Y_UP",
                    source_sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest()), corrected

    def render(self, filepath, frame, side_view=False):
        self.scene.frame_set(frame)
        scene = self.scene
        scene.render.engine = "CYCLES"
        scene.cycles.device, scene.cycles.samples = "CPU", 24
        scene.render.resolution_x, scene.render.resolution_y = 800, 650
        scene.render.resolution_percentage = 100
        if scene.world is None:
            scene.world = bpy.data.worlds.new("PreviewWorld")
        scene.world.use_nodes = True
        scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.16, 0.18, 0.21, 1)
        scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
        center = self.arm.matrix_world @ Vector((0, 1.55, 0))
        direction = Vector((9, 3, 0)) if side_view else Vector((8, 5, -8))
        bpy.ops.object.camera_add(location=center + self.arm.matrix_world.to_3x3() @ direction)
        camera = bpy.context.object
        camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.type, camera.data.ortho_scale = "ORTHO", 7.3
        scene.camera = camera
        bpy.ops.object.light_add(type="AREA", location=center + self.arm.matrix_world.to_3x3() @ Vector((4, 6, 4)))
        light = bpy.context.object
        light.data.energy, light.data.size = 1800, 5
        light.rotation_euler = (center - light.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(filepath)
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(camera, do_unlink=True)
        bpy.data.objects.remove(light, do_unlink=True)


def write_report(path, report):
    path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
