"""Build editable Blender poker models and Godot-ready GLB assets.

Run with Blender: blender -b --factory-startup --python tools/build_poker_models.py
Cards are modeled as 63 x 88 x 1.3 mm rounded solids with independent UV face/back.
"""

from pathlib import Path
import json
import bpy

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "client/game_framework/card3d/assets/models"
EDITABLE = ROOT / "SourceAssets/Poker"
MODELS.mkdir(parents=True, exist_ok=True)
EDITABLE.mkdir(parents=True, exist_ok=True)


def material(name, rgba, roughness=0.4, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = rgba
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    return mat


def bevel_cube(name, dimensions, location, mat, bevel):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    mod = obj.modifiers.new("Real rounded profile", "BEVEL")
    mod.width = bevel
    mod.segments = 5
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod = obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def uv_panel(name, z, width, height, mat, reverse=False):
    vertices = [(-width/2, -height/2, z), (width/2, -height/2, z),
                (width/2, height/2, z), (-width/2, height/2, z)]
    if reverse:
        vertices = list(reversed(vertices))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], [(0, 1, 2, 3)])
    mesh.update()
    uv = mesh.uv_layers.new(name="PokerUV")
    coords = [(0, 0), (1, 0), (1, 1), (0, 1)]
    if reverse:
        coords = list(reversed(coords))
    for index, loop in enumerate(mesh.polygons[0].loop_indices):
        uv.data[loop].uv = coords[index]
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def save_and_export(stem):
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(EDITABLE / (stem + ".blend")))
    bpy.ops.export_scene.gltf(filepath=str(MODELS / (stem + ".glb")), export_format="GLB", export_apply=True)


def build_card():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    paper = material("M_Poker_LaminatedPaper", (0.96, 0.95, 0.90, 1), 0.28)
    face = material("M_Poker_Face_ReplaceAtRuntime", (1, 1, 1, 1), 0.3)
    back = material("M_Poker_Back_ReplaceAtRuntime", (0.08, 0.18, 0.31, 1), 0.32)
    bevel_cube("CardBody_63x88x1.3mm", (0.063, 0.088, 0.0013), (0, 0, 0), paper, 0.0021)
    uv_panel("CardFace", 0.000665, 0.0600, 0.0850, face)
    uv_panel("CardBack", -0.000665, 0.0600, 0.0850, back, reverse=True)
    save_and_export("poker_card")


def cylinder(name, radius, depth, location, mat, vertices=96, bevel=0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new("Rounded rim", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def build_table():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    wood = material("M_Table_DarkWalnut", (0.115, 0.049, 0.026, 1), 0.31)
    wood_edge = material("M_Table_WalnutInlay", (0.28, 0.12, 0.055, 1), 0.27)
    felt = material("M_Table_DeepGreenFelt", (0.012, 0.075, 0.055, 1), 0.85)
    brass = material("M_Table_Brass", (0.7, 0.46, 0.16, 1), 0.29, 0.63)
    base = cylinder("SolidWalnutTable", 1, 0.07, (0, 0, -0.067), wood, bevel=0.018)
    base.scale.x, base.scale.y = 0.82, 1.05
    felt_obj = cylinder("FeltPlayingSurface", 1, 0.008, (0, 0, -0.027), felt, bevel=0.002)
    felt_obj.scale.x, felt_obj.scale.y = 0.755, 0.975
    for label, radius, z, thickness, mat in [("PolishedWoodRail", 1, -0.035, 0.012, wood_edge), ("BrassOuterAccent", 1, -0.029, 0.002, brass)]:
        ring = bpy.data.curves.new(label, "CURVE")
        ring.dimensions = "3D"
        ring.bevel_depth = thickness / 2
        ring.bevel_resolution = 3
        spline = ring.splines.new("POLY")
        spline.points.add(127)
        import math
        for i, point in enumerate(spline.points):
            angle = i * math.tau / 128
            rx = 0.79 if label == "PolishedWoodRail" else 0.768
            ry = 1.015 if label == "PolishedWoodRail" else 0.990
            point.co = (rx * math.cos(angle), ry * math.sin(angle), z, 1)
        spline.use_cyclic_u = True
        obj = bpy.data.objects.new(label, ring)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(mat)
    save_and_export("poker_table")


build_card()
build_table()
(MODELS / "model_manifest.json").write_text(json.dumps({
    "card": "poker_card.glb", "table": "poker_table.glb", "card_dimensions_m": [0.063, 0.088, 0.0013],
    "card_face_node": "CardFace", "card_back_node": "CardBack", "source": "SourceAssets/Poker"
}, ensure_ascii=False, indent=2), encoding="utf-8")
print("POKER_MODELS_READY")
