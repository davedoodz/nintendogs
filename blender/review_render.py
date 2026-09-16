"""Temporary camera/light/floor for pose review; never saved or exported."""
import bpy
from mathutils import Vector


def render_review(rig, path, frame, front=False):
    rig.scene.frame_set(frame)
    scene = rig.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device, scene.cycles.samples = 'CPU', 24
    scene.render.resolution_x, scene.render.resolution_y = 800, 650
    scene.render.resolution_percentage = 100
    if scene.world is None:
        scene.world = bpy.data.worlds.new('ReviewWorld')
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.16,.18,.21,1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value = .8
    temporary = []
    center = rig.arm.matrix_world @ Vector((0, 1.4, 0))
    direction = Vector((2, 2, 10) if front else (9, 2, 1))
    bpy.ops.object.camera_add(location=center + rig.arm.matrix_world.to_3x3() @ direction)
    camera = bpy.context.object
    temporary.append(camera)
    camera.rotation_euler = (center-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type, camera.data.ortho_scale = 'ORTHO', 6.4
    scene.camera = camera
    bpy.ops.object.light_add(type='AREA', location=center + rig.arm.matrix_world.to_3x3() @ Vector((4,6,4)))
    light = bpy.context.object
    temporary.append(light)
    light.data.energy, light.data.size = 1800, 5
    light.rotation_euler = (center-light.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0,0,0))
    temporary.append(bpy.context.object)
    try:
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
    finally:
        for obj in temporary:
            data = obj.data
            kind = obj.type
            bpy.data.objects.remove(obj, do_unlink=True)
            if kind == 'CAMERA': bpy.data.cameras.remove(data)
            elif kind == 'LIGHT': bpy.data.lights.remove(data)
            else: bpy.data.meshes.remove(data)
