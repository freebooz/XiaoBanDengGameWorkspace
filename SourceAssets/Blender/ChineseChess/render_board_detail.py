"""Render the saved board unobstructed and a real groove close-up via Blender MCP."""
from pathlib import Path
import bpy
from mathutils import Vector

root = Path(__file__).resolve().parent
scene = bpy.context.scene
camera = scene.camera
old_matrix = camera.matrix_world.copy()
old_type, old_lens, old_scale = camera.data.type, camera.data.lens, camera.data.ortho_scale
old_path = scene.render.filepath
old_size = (scene.render.resolution_x, scene.render.resolution_y)
pieces = list(bpy.data.collections["03 | Opening arrangement preview"].objects)
try:
    for obj in pieces:
        obj.hide_render = True
    camera.location = (0, -0.31, 0.54)
    camera.rotation_euler = (Vector((0, 0, 0.013)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 0.465
    scene.render.resolution_x, scene.render.resolution_y = 1400, 1400
    scene.render.filepath = str(root / "XBD_ChessBoard_engraved_preview.png")
    bpy.ops.render.render(write_still=True)
    camera.location = (-0.11, -0.225, 0.165)
    camera.rotation_euler = (Vector((-0.055, -0.13, 0.020)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = 0.13
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1050
    scene.render.filepath = str(root / "XBD_ChessBoard_groove_detail.png")
    bpy.ops.render.render(write_still=True)
finally:
    for obj in pieces:
        obj.hide_render = False
    camera.matrix_world = old_matrix
    camera.data.type, camera.data.lens, camera.data.ortho_scale = old_type, old_lens, old_scale
    scene.render.resolution_x, scene.render.resolution_y = old_size
    scene.render.filepath = old_path
print("BOARD_DETAIL_RENDERS_SAVED")
