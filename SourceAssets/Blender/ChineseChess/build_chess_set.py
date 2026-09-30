"""Build the editable xiangqi set and Godot glTF assets from a blank Blender scene."""

import math
import os
import uuid
import numpy as np
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector


ROOT = Path(__file__).resolve().parent
WORKSPACE = ROOT.parents[2]
ASSETS = WORKSPACE / "client/games/chinese_chess/assets"
MODELS = ASSETS / "models"
MODELS.mkdir(parents=True, exist_ok=True)
BLEND = ROOT / "XBD_ChineseChess_Set.blend"
PREVIEW = ROOT / "XBD_ChineseChess_Set_preview.png"
BOARD_IMAGE = ASSETS / "board_reference_surface.png"
FRAME_IMAGE = ASSETS / "red_sandalwood_woodgrain.png"
BOARD_NORMAL_IMAGE = ASSETS / "red_sandalwood_woodgrain_normal.png"
BOARD_ROUGHNESS_IMAGE = ASSETS / "red_sandalwood_woodgrain_roughness.png"
PIECE_IMAGE = ASSETS / "golden_nanmu_fine.png"
PIECE_FINISH_IMAGE = ASSETS / "golden_nanmu_lacquer_color.png"
PIECE_NORMAL_IMAGE = ASSETS / "golden_nanmu_fine_normal.png"
PIECE_ROUGHNESS_IMAGE = ASSETS / "golden_nanmu_fine_roughness.png"
FONT_FILE = Path("C:/Windows/Fonts/simkai.ttf")
PACKED_TEXTURES = {}


def packed_texture(path, non_color=False):
    key = (path.as_posix(), non_color)
    if key not in PACKED_TEXTURES:
        image = bpy.data.images.load(path.as_posix(), check_existing=False)
        if non_color:
            image.colorspace_settings.name = "Non-Color"
        image.pack()
        PACKED_TEXTURES[key] = image
    return PACKED_TEXTURES[key]

CELL = 0.050
TOP = 0.020
BOARD_W = 0.530
BOARD_H = 0.580

existing_opening = bpy.data.collections.get("03 | Opening arrangement preview")
if bpy.data.filepath and Path(bpy.data.filepath).name == BLEND.name and existing_opening and len(existing_opening.objects) == 32:
    if bpy.data.objects.get("Frame | continuous red sandalwood rim"):
        bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "XBD_ChineseChess_RedSandalwood_Archive.blend"), copy=True)
    before_correction = ROOT / "XBD_ChineseChess_BeforeFlushCorrection.blend"
    if not before_correction.exists():
        bpy.ops.wm.save_as_mainfile(filepath=before_correction.as_posix(), copy=True)

for obj in tuple(bpy.data.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
for old_collection in tuple(bpy.data.collections):
    bpy.data.collections.remove(old_collection)
for old_material in tuple(bpy.data.materials):
    bpy.data.materials.remove(old_material)
for old_image in tuple(bpy.data.images):
    if old_image.name != "Render Result":
        bpy.data.images.remove(old_image)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1400
scene.render.resolution_y = 1400
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.render.filepath = PREVIEW.as_posix()
scene.view_settings.view_transform = "Khronos PBR Neutral"
scene.view_settings.exposure = 0.0
scene.world = bpy.data.worlds.new("Warm studio world")
scene.world.use_nodes = True
next(n for n in scene.world.node_tree.nodes if n.type == "BACKGROUND").inputs["Color"].default_value = (0.18, 0.13, 0.09, 1)
next(n for n in scene.world.node_tree.nodes if n.type == "BACKGROUND").inputs["Strength"].default_value = 0.32


def collection(name):
    result = bpy.data.collections.new(name)
    scene.collection.children.link(result)
    return result


BOARD = collection("01 | Engraved red sandalwood board")
TEMPLATES = collection("02 | Fourteen piece masters (36 mm x 10 mm)")
PREVIEW_PIECES = collection("03 | Opening arrangement preview")
STUDIO = collection("04 | Preview camera and lights")
LINE_CUTTERS = []


def relink(obj, target):
    for old in tuple(obj.users_collection):
        old.objects.unlink(obj)
    target.objects.link(obj)
    return obj


def principled(name, color, roughness=0.43, metallic=0.0, coat=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = next(node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Coat Weight"].default_value = coat
    shader.inputs["Coat Roughness"].default_value = 0.22
    return mat


def generate_piece_pbr_maps():
    """Derive normal/roughness maps from the golden nanmu albedo texture."""
    if not PIECE_IMAGE.exists():
        return

    source = bpy.data.images.load(str(PIECE_IMAGE), check_existing=False)
    width, height = source.size
    pixels = np.asarray(source.pixels[:], dtype=np.float32).reshape((height, width, 4))
    rgb = pixels[:, :, :3]
    # Preserve only 25% nanmu grain contrast beneath the yellow lacquer finish.
    mean_color = np.mean(rgb, axis=(0, 1), keepdims=True)
    restrained_color = pixels.copy()
    restrained_color[:, :, :3] = np.clip(mean_color + (rgb-mean_color)*.25, 0, 1)
    luminance = rgb[:, :, 0] * 0.2126 + rgb[:, :, 1] * 0.7152 + rgb[:, :, 2] * 0.0722

    dx = (np.roll(luminance, -1, axis=1) - np.roll(luminance, 1, axis=1)) * 2.4
    dy = (np.roll(luminance, -1, axis=0) - np.roll(luminance, 1, axis=0)) * 2.4
    nx = -dx
    ny = -dy
    nz = np.ones_like(luminance) * 1.55
    length = np.sqrt(nx * nx + ny * ny + nz * nz)

    normal = np.zeros((height, width, 4), dtype=np.float32)
    normal[:, :, 0] = nx / length * 0.5 + 0.5
    normal[:, :, 1] = ny / length * 0.5 + 0.5
    normal[:, :, 2] = nz / length * 0.5 + 0.5
    normal[:, :, 3] = 1.0

    local_variation = np.abs(dx) + np.abs(dy)
    # Lacquer seals the wood: retain very gentle roughness variation under the coat.
    roughness = np.clip(0.20 + (1.0 - luminance) * 0.045 + local_variation * 0.08, 0.20, 0.28)
    rough = np.empty((height, width, 4), dtype=np.float32)
    rough[:, :, 0] = roughness
    rough[:, :, 1] = roughness
    rough[:, :, 2] = roughness
    rough[:, :, 3] = 1.0

    def save_map(name, path, data):
        image = bpy.data.images.new(name, width=width, height=height, alpha=True, float_buffer=False)
        image.colorspace_settings.name = "sRGB" if path == PIECE_FINISH_IMAGE else "Non-Color"
        image.pixels.foreach_set(data.reshape(-1))
        image.filepath_raw = str(path)
        image.file_format = "PNG"
        image.save()
        bpy.data.images.remove(image)

    save_map("GoldenNanmu_LacquerColor", PIECE_FINISH_IMAGE, restrained_color)
    save_map("GoldenNanmu_Normal", PIECE_NORMAL_IMAGE, normal)
    save_map("GoldenNanmu_Roughness", PIECE_ROUGHNESS_IMAGE, rough)
    bpy.data.images.remove(source)


generate_piece_pbr_maps()


def apply_piece_pbr_textures(material):
    shader = next(node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    if PIECE_NORMAL_IMAGE.exists():
        normal_texture = material.node_tree.nodes.new("ShaderNodeTexImage")
        normal_texture.image = packed_texture(PIECE_NORMAL_IMAGE, True)
        normal_texture.image.colorspace_settings.name = "Non-Color"
        normal_texture.image.pack()
        normal_node = material.node_tree.nodes.new("ShaderNodeNormalMap")
        normal_node.inputs["Strength"].default_value = 0.08
        normal_node.uv_map = "UV0_Nanmu"
        coordinates = material.node_tree.nodes.new("ShaderNodeUVMap")
        coordinates.uv_map = "UV0_Nanmu"
        material.node_tree.links.new(coordinates.outputs["UV"], normal_texture.inputs["Vector"])
        material.node_tree.links.new(normal_texture.outputs["Color"], normal_node.inputs["Color"])
        material.node_tree.links.new(normal_node.outputs["Normal"], shader.inputs["Normal"])
    if PIECE_ROUGHNESS_IMAGE.exists():
        rough_texture = material.node_tree.nodes.new("ShaderNodeTexImage")
        rough_texture.image = packed_texture(PIECE_ROUGHNESS_IMAGE, True)
        rough_texture.image.colorspace_settings.name = "Non-Color"
        rough_texture.image.pack()
        coordinates = material.node_tree.nodes.new("ShaderNodeUVMap")
        coordinates.uv_map = "UV0_Nanmu"
        material.node_tree.links.new(coordinates.outputs["UV"], rough_texture.inputs["Vector"])
        material.node_tree.links.new(rough_texture.outputs["Color"], shader.inputs["Roughness"])


def generate_board_pbr_maps():
    """Generate subtle red-sandalwood normal/roughness maps for the board surface and bevels."""
    if not FRAME_IMAGE.exists():
        return

    source = bpy.data.images.load(str(FRAME_IMAGE), check_existing=False)
    width, height = source.size
    pixels = np.asarray(source.pixels[:], dtype=np.float32).reshape((height, width, 4))
    rgb = pixels[:, :, :3]
    luminance = rgb[:, :, 0] * 0.2126 + rgb[:, :, 1] * 0.7152 + rgb[:, :, 2] * 0.0722

    dx = (np.roll(luminance, -1, axis=1) - np.roll(luminance, 1, axis=1)) * 1.45
    dy = (np.roll(luminance, -1, axis=0) - np.roll(luminance, 1, axis=0)) * 1.45
    nx = -dx
    ny = -dy
    nz = np.ones_like(luminance) * 2.0
    length = np.sqrt(nx * nx + ny * ny + nz * nz)

    normal = np.zeros((height, width, 4), dtype=np.float32)
    normal[:, :, 0] = nx / length * 0.5 + 0.5
    normal[:, :, 1] = ny / length * 0.5 + 0.5
    normal[:, :, 2] = nz / length * 0.5 + 0.5
    normal[:, :, 3] = 1.0

    local_variation = np.abs(dx) + np.abs(dy)
    roughness = np.clip(0.36 + (1.0 - luminance) * 0.14 + local_variation * 0.22, 0.32, 0.62)
    rough = np.empty((height, width, 4), dtype=np.float32)
    rough[:, :, 0] = roughness
    rough[:, :, 1] = roughness
    rough[:, :, 2] = roughness
    rough[:, :, 3] = 1.0

    def save_map(name, path, data):
        image = bpy.data.images.new(name, width=width, height=height, alpha=True, float_buffer=False)
        image.colorspace_settings.name = "Non-Color"
        image.pixels.foreach_set(data.reshape(-1))
        image.filepath_raw = str(path)
        image.file_format = "PNG"
        image.save()
        bpy.data.images.remove(image)

    save_map("RedSandalwood_Normal", BOARD_NORMAL_IMAGE, normal)
    save_map("RedSandalwood_Roughness", BOARD_ROUGHNESS_IMAGE, rough)
    bpy.data.images.remove(source)


generate_board_pbr_maps()


def apply_board_pbr_textures(material):
    shader = next(node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    if BOARD_NORMAL_IMAGE.exists():
        normal_texture = material.node_tree.nodes.new("ShaderNodeTexImage")
        normal_texture.image = packed_texture(BOARD_NORMAL_IMAGE, True)
        normal_texture.image.colorspace_settings.name = "Non-Color"
        normal_texture.image.pack()
        normal_node = material.node_tree.nodes.new("ShaderNodeNormalMap")
        normal_node.inputs["Strength"].default_value = 0.32
        material.node_tree.links.new(normal_texture.outputs["Color"], normal_node.inputs["Color"])
        material.node_tree.links.new(normal_node.outputs["Normal"], shader.inputs["Normal"])
    if BOARD_ROUGHNESS_IMAGE.exists():
        rough_texture = material.node_tree.nodes.new("ShaderNodeTexImage")
        rough_texture.image = packed_texture(BOARD_ROUGHNESS_IMAGE, True)
        rough_texture.image.colorspace_settings.name = "Non-Color"
        rough_texture.image.pack()
        material.node_tree.links.new(rough_texture.outputs["Color"], shader.inputs["Roughness"])


wood = principled("Board | supplied reference playing surface", (0.48, 0.19, 0.10), 0.40, 0, 0.20)
if BOARD_IMAGE.exists():
    texture = wood.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = packed_texture(BOARD_IMAGE)
    texture.image.pack()
    shader = next(node for node in wood.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    wood.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])

edge_wood = principled("Board | matching reference wood sides", (0.48, 0.19, 0.10), 0.40, 0, 0.20)
if BOARD_IMAGE.exists():
    texture = edge_wood.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = packed_texture(BOARD_IMAGE)
    texture.image.pack()
    shader = next(node for node in edge_wood.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    edge_wood.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
for material in (wood, edge_wood):
    next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Coat Roughness"].default_value = .24
relief = principled("Board | polished red sandalwood relief", (0.17, 0.032, 0.016), 0.31, 0.0, 0.26)
gold_detail = principled("Carving | antique golden nanmu corner inlays", (0.43, 0.23, 0.07), 0.31, 0.10, 0.12)
shade = principled("Board | incised near-black lines", (0.065, 0.025, 0.016), 0.7)
# A smooth transparent lacquer layer sits above the subtle golden wood grain.
piece_wood = principled("Pieces | golden nanmu woodgrain", (0.78, 0.48, 0.16), 0.23, 0, 0.58)
if PIECE_IMAGE.exists():
    texture = piece_wood.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = packed_texture(PIECE_FINISH_IMAGE)
    texture.image.pack()
    coordinates = piece_wood.node_tree.nodes.new("ShaderNodeUVMap")
    coordinates.uv_map = "UV0_Nanmu"
    piece_wood.node_tree.links.new(coordinates.outputs["UV"], texture.inputs["Vector"])
    shader = next(node for node in piece_wood.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    piece_wood.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
apply_piece_pbr_textures(piece_wood)
piece_face = principled("Pieces | golden nanmu wood face", (0.80, 0.51, 0.18), 0.23, 0, 0.58)
if PIECE_IMAGE.exists():
    texture = piece_face.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = packed_texture(PIECE_FINISH_IMAGE)
    texture.image.pack()
    coordinates = piece_face.node_tree.nodes.new("ShaderNodeUVMap")
    coordinates.uv_map = "UV0_Nanmu"
    piece_face.node_tree.links.new(coordinates.outputs["UV"], texture.inputs["Vector"])
    shader = next(node for node in piece_face.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    piece_face.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
apply_piece_pbr_textures(piece_face)
ring_red = principled("Pieces | cinnabar concentric line", (0.50, 0.054, 0.022), 0.35, 0.01, 0.15)
black_ink = principled("Black side | carved ink", (0.019, 0.015, 0.009), 0.49)
red_ink = principled("Red side | carved cinnabar", (0.49, 0.019, 0.014), 0.44)
for mat in (black_ink, red_ink, shade):
    next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Specular IOR Level"].default_value = 0.12
for mat in (piece_wood, piece_face):
    next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Coat Roughness"].default_value = 0.12


def bevel_box(name, at, dimensions, material, radius=0.0016, segments=3, target=BOARD):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    obj = relink(bpy.context.object, target)
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    if radius > 0:
        modifier = obj.modifiers.new("Hand softened edges", "BEVEL")
        modifier.width = radius
        modifier.segments = segments
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
    return obj


def weld_closed_mesh(obj):
    """Curve caps have coincident, disconnected vertices after conversion."""
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    bmesh.ops.remove_doubles(mesh, verts=list(mesh.verts), dist=1e-7)
    bmesh.ops.recalc_face_normals(mesh, faces=list(mesh.faces))
    open_edges = sum(not edge.is_manifold for edge in mesh.edges)
    mesh.to_mesh(obj.data)
    mesh.free()
    obj.data.update()
    return open_edges


def tube(name, points, thickness, material, target=BOARD, cyclic=False):
    if name.startswith(("Grid |", "Palace |", "Cannon post |", "Soldier post |")):
        cutter = tube("Cut | " + name, [(p[0], p[1], TOP - 0.00015) for p in points], thickness, material, target, cyclic)
        LINE_CUTTERS.append((name, cutter))
        return tube("Inlay | " + name, [(p[0], p[1], TOP - 0.00055) for p in points], thickness * 0.60, material, target, cyclic)
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 12
    curve.bevel_depth = thickness / 2
    curve.bevel_resolution = 2
    curve.use_fill_caps = True
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for i, point in enumerate(points):
        spline.points[i].co = (*point, 1)
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, curve)
    target.objects.link(obj)
    obj.data.materials.append(material)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    weld_closed_mesh(obj)
    return obj


def lettering(name, value, at, size, material, target=BOARD, align="CENTER", extrude=0.00024, outline=None, bevel_depth=0.00005):
    font = bpy.data.curves.new(name, "FONT")
    font.body = value
    font.size = size
    font.align_x = align
    font.align_y = "CENTER"
    font.extrude = extrude
    font.bevel_depth = bevel_depth
    font.bevel_resolution = 1
    font.offset = outline if outline is not None else (0.00024 if target == TEMPLATES else 0.00014)
    if FONT_FILE.exists():
        font.font = bpy.data.fonts.load(str(FONT_FILE), check_existing=True)
        font.font.pack()
    obj = bpy.data.objects.new(name, font)
    target.objects.link(obj)
    obj.location = at
    obj.data.materials.append(material)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    return obj


def carve(target, cutters, label):
    print("Carving:", label, flush=True)
    bpy.ops.object.select_all(action="DESELECT")
    for cutter in cutters:
        cutter.select_set(True)
    bpy.context.view_layer.objects.active = cutters[0]
    if len(cutters) > 1:
        bpy.ops.object.join()
    cutter = bpy.context.view_layer.objects.active
    open_edges = weld_closed_mesh(cutter)
    if open_edges:
        raise RuntimeError(f"{label}: cutter has {open_edges} non-manifold edges")
    modifier = target.modifiers.new(label, "BOOLEAN")
    modifier.operation = "DIFFERENCE"
    modifier.solver = "MANIFOLD"
    modifier.object = cutter
    modifier.use_self = True
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    target.data.validate(verbose=False, clean_customdata=True)
    target.data.update()
    bpy.data.objects.remove(cutter, do_unlink=True)


# Read the source intersections before building geometry. One affine image
# projection covers the entire top; geometry follows the source instead of
# stretching individual image regions to fit an assumed uniform grid.
reference = packed_texture(BOARD_IMAGE)
image_width, image_height = reference.size
pixels = np.asarray(reference.pixels[:], dtype=np.float32).reshape(image_height, image_width, 4)[::-1, :, :3]
luminance = pixels[:, :, 0] * .2126 + pixels[:, :, 1] * .7152 + pixels[:, :, 2] * .0722
vertical_profile = np.median(luminance[[170,280,402,514,730,840,950,1064], :], axis=0)
horizontal_profile = np.median(luminance[:, [180,300,420,800,925,1060]], axis=1)

def line_centers(profile, approximate):
    centers = []
    for point in approximate:
        start = point - 20
        span = profile[start:point + 21]
        threshold = float(span.min() + .035 * (span.max() - span.min()))
        dark_indices = np.where(span <= threshold)[0]
        bands = np.split(dark_indices, np.where(np.diff(dark_indices) > 1)[0] + 1)
        nearest = min(bands, key=lambda band: abs(start + band.mean() - point))
        centers.append(float(start + nearest.mean()))
    return centers

file_pixels = line_centers(vertical_profile, [125,251,376,501,626,752,876,1002,1128])
rank_pixels = line_centers(horizontal_profile, [112,231,347,461,563,677,784,895,1009,1125])
GRID_X = -.160 + (np.asarray(file_pixels) - file_pixels[0]) * .320 / (file_pixels[-1] - file_pixels[0])
GRID_Y = .180 - (np.asarray(rank_pixels) - rank_pixels[0]) * .360 / (rank_pixels[-1] - rank_pixels[0])
assert np.all(np.diff(GRID_X) > 0) and np.all(np.diff(GRID_Y) < 0)
print('REGISTERED_REFERENCE_GRID', file_pixels, rank_pixels)
for material in (wood, edge_wood):
    for node in material.node_tree.nodes:
        if node.type == 'TEX_IMAGE':
            node.extension = 'EXTEND'

# A single 6 mm rectangular plate, with only four micro-rounded corners.
# Final 0.412 x 0.452 m leaves 28 mm beyond the outer pieces on every side.
playfield = bevel_box("Board | red sandalwood flat plate", (0, 0, TOP - 0.003), (0.515, 0.565, 0.006), wood, 0)
playfield.data.materials.append(edge_wood)
split = bmesh.new()
split.from_mesh(playfield.data)
corner_edges = [edge for edge in split.edges if abs((edge.verts[1].co-edge.verts[0].co).z) > .005]
bmesh.ops.bevel(split, geom=corner_edges, offset=.0075, offset_type="OFFSET", segments=32, profile=.5, clamp_overlap=True, affect="EDGES")
bmesh.ops.recalc_face_normals(split, faces=list(split.faces))
split.to_mesh(playfield.data)
split.free()
playfield.data.update()
for polygon in playfield.data.polygons:
    polygon.material_index = 0 if polygon.normal.z > .5 else 1
    for loop_index in polygon.loop_indices:
        vertex = playfield.data.vertices[playfield.data.loops[loop_index].vertex_index].co
        if abs(polygon.normal.z) > .5:
            mapped = (vertex.x / 0.515 + 0.5, vertex.y / 0.565 + 0.5)
        elif abs(polygon.normal.x) > .5:
            mapped = (vertex.y / 0.565 + 0.5, vertex.z / 0.006 + 0.5)
        else:
            mapped = (vertex.x / 0.515 + 0.5, vertex.z / 0.006 + 0.5)
        playfield.data.uv_layers.active.data[loop_index].uv = mapped

# Standard 9 x 10 xiangqi intersections. Inner files stop at the river.
for row in range(10):
    y = GRID_Y[row] / .8
    tube("Grid | rank %02d" % row, [(GRID_X[0] / .8, y, TOP + 0.0008), (GRID_X[-1] / .8, y, TOP + 0.0008)], 0.00125, shade)
for col in range(9):
    x = GRID_X[col] / .8
    spans = [(GRID_Y[-1] / .8, GRID_Y[0] / .8)] if col in (0, 8) else [(GRID_Y[-1] / .8, GRID_Y[5] / .8), (GRID_Y[4] / .8, GRID_Y[0] / .8)]
    for part, (a, b) in enumerate(spans):
        tube("Grid | file %02d / %d" % (col, part), [(x, a, TOP + 0.0008), (x, b, TOP + 0.0008)], 0.00125, shade)
for start_row in (0, 7):
    for sign in (-1, 1):
        rows = (start_row, start_row + 2) if sign == -1 else (start_row + 2, start_row)
        tube("Palace | %s / %s" % (start_row, sign), [(GRID_X[3] / .8, GRID_Y[rows[0]] / .8, TOP + 0.00082), (GRID_X[5] / .8, GRID_Y[rows[1]] / .8, TOP + 0.00082)], 0.00125, shade)

# Incised target brackets at cannon and soldier posts, with no mark outside the board.
for row in (2, 7):
    for col in (1, 7):
        x, y = GRID_X[col] / .8, GRID_Y[row] / .8
        for sx in (-1, 1):
            for sy in (-1, 1):
                a = (x + sx * 0.004, y + sy * 0.004, TOP + 0.00085)
                b = (x + sx * 0.009, y + sy * 0.004, TOP + 0.00085)
                c = (x + sx * 0.004, y + sy * 0.009, TOP + 0.00085)
                tube("Cannon post | %d %d %d %d" % (row, col, sx, sy), [b, a, c], 0.0010, shade)
for row in (3, 6):
    for col in (0, 2, 4, 6, 8):
        x, y = GRID_X[col] / .8, GRID_Y[row] / .8
        for sx in (-1, 1):
            if col == 0 and sx < 0 or col == 8 and sx > 0:
                continue
            for sy in (-1, 1):
                a = (x + sx * 0.004, y + sy * 0.004, TOP + 0.00085)
                tube("Soldier post | %d %d %d %d" % (row, col, sx, sy), [(a[0] + sx * 0.004, a[1], a[2]), a, (a[0], a[1] + sy * 0.004, a[2])], 0.0010, shade)

# The latest corrected reference controls the river lettering and ornaments.

# Genuine subtractive channels: five disconnected cutter groups avoid ambiguous
# self-intersections at the rank/file and palace crossings. Dark inlays stay below
# the original wooden surface and do not substitute for the carved geometry.
for group, predicate in [
    ("ranks", lambda name: name.startswith("Grid | rank")),
    ("files", lambda name: name.startswith("Grid | file")),
    ("palace_a", lambda name: name.startswith("Palace |") and name.endswith("/ -1")),
    ("palace_b", lambda name: name.startswith("Palace |") and name.endswith("/ 1")),
    ("target_marks", lambda name: name.startswith(("Cannon post |", "Soldier post |"))),
]:
    carve(playfield, [obj for name, obj in LINE_CUTTERS if predicate(name)], "Engraved " + group)
playfield["grid_engraving_depth_m"] = 0.000775
playfield["grid_engraving_width_m"] = 0.0010
playfield["piece_edge_clearance_m"] = 0.028
playfield["base_removed"] = True
playfield["outer_bevel_m"] = 0.0
playfield["four_corner_bevel_m"] = 0.0060
playfield["river_text_orientation"] = "exact latest user reference orientation"
playfield["river_texture_panels"] = "latest corrected reference retained without text changes"
playfield["surface_image"] = BOARD_IMAGE.name

# Uniform planar projection: no region-specific UV knots or shearing.
playfield['source_grid_file_pixels']=file_pixels
playfield['source_grid_rank_pixels']=rank_pixels
playfield['grid_x_m'] = GRID_X.tolist()
playfield['grid_y_m'] = GRID_Y.tolist()
playfield['surface_mapping'] = 'single affine planar UV projection'

def side_perimeter_u(x, y):
    # Continuous clockwise unwrap, including the actual circular corners.
    hw, hh, r = .515 / 2, .565 / 2, .0075
    a, b, q = .515 - 2 * r, .565 - 2 * r, math.pi * r / 2
    if y >= hh - 1e-7:
        s = x + hw - r
    elif x >= hw-r-1e-7 and y >= hh-r-1e-7:
        s = a + r * (math.pi/2 - math.atan2(y-hh+r, x-hw+r))
    elif x >= hw-r-1e-7 and y <= -hh+r+1e-7:
        s = a+q+b + r * -math.atan2(y+hh-r, x-hw+r)
    elif x <= -hw+r+1e-7 and y <= -hh+r+1e-7:
        s = 2*a+b+2*q + r * (-math.pi/2 - math.atan2(y+hh-r, x+hw-r))
    elif x <= -hw+r+1e-7 and y >= hh-r-1e-7:
        s = 2*a+2*b+3*q + r * (math.pi - math.atan2(y-hh+r, x+hw-r))
    elif x >= hw-r:
        s = a+q+hh-r-y
    elif y <= -hh+r:
        s = a+b+2*q+hw-r-x
    else:
        s = 2*a+b+3*q+y+hh-r
    return s / (2*a + 2*b + 4*q)

for polygon in playfield.data.polygons:
    polygon.use_smooth = False
    center = polygon.center
    perimeter_values = [side_perimeter_u(playfield.data.vertices[playfield.data.loops[i].vertex_index].co.x, playfield.data.vertices[playfield.data.loops[i].vertex_index].co.y) for i in polygon.loop_indices] if polygon.material_index == 1 else []
    crosses_seam = bool(perimeter_values) and max(perimeter_values)-min(perimeter_values) > .5
    for loop_index in polygon.loop_indices:
        vertex = playfield.data.vertices[playfield.data.loops[loop_index].vertex_index].co
        if polygon.material_index == 0:
            u = (file_pixels[0] + (vertex.x * .8 + .160) / .320 * (file_pixels[-1] - file_pixels[0])) / image_width
            v = 1 - (rank_pixels[0] + (.180 - vertex.y * .8) / .360 * (rank_pixels[-1] - rank_pixels[0])) / image_height
            playfield.data.uv_layers.active.data[loop_index].uv = (u,v)
        else:
            # Exact supplied wood strip, continuously unwrapped around all corners.
            along = side_perimeter_u(vertex.x, vertex.y)
            if crosses_seam and along < .5:
                along += 1
            playfield.data.uv_layers.active.data[loop_index].uv = (along, .012 + (vertex.z/.006+.5)*.012)

for board_part in BOARD.objects:
    board_part.location.x *= 0.8
    board_part.location.y *= 0.8
    board_part.scale.x *= 0.8
    board_part.scale.y *= 0.8
CELL = 0.040


def piece_mesh(name):
    # Hand shaped lathe: shallow underside, rounded 10 mm rim and a recessed face.
    profile = [
        (0.0129, 0.0000), (0.0143, 0.0007),
        (0.0154, 0.0020), (0.0160, 0.0037), (0.0160, 0.0058),
        (0.0155, 0.0074), (0.0144, 0.0087), (0.0132, 0.0092),
        (0.0128, 0.0100),
    ]
    count = 64
    vertices = [(r * math.cos(math.tau * j / count), r * math.sin(math.tau * j / count), z) for r, z in profile for j in range(count)]
    faces = []
    for i in range(len(profile) - 1):
        for j in range(count):
            faces.append((i * count + j, i * count + (j + 1) % count, (i + 1) * count + (j + 1) % count, (i + 1) * count + j))
    faces.append(tuple(reversed(range(count))))
    faces.append(tuple((len(profile) - 1) * count + j for j in range(count)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    uv = mesh.uv_layers.new(name="UV0_Nanmu")
    side_face_count = (len(profile) - 1) * count
    top_face_index = side_face_count + 1
    max_height = profile[-1][1]
    top_radius = profile[-1][0]
    bottom_radius = profile[0][0]

    # 侧壁使用真正圆柱展开，顶/底面使用独立平面投影。
    # 旧实现把 x/y/z 直接混入同一 UV，圆周侧面会发生严重拉伸和糊纹。
    for polygon in mesh.polygons:
        if polygon.index < side_face_count:
            loop_values = []
            raw_u = []
            for loop_index in polygon.loop_indices:
                vertex_index = mesh.loops[loop_index].vertex_index
                vertex = mesh.vertices[vertex_index].co
                ring_index = vertex_index % count
                u_value = ring_index / float(count)
                raw_u.append(u_value)
                loop_values.append((loop_index, vertex))

            # 处理 63→0 的圆柱接缝，避免一个四边形横跨整张贴图插值。
            if max(raw_u) - min(raw_u) > 0.5:
                raw_u = [value + 1.0 if value < 0.5 else value for value in raw_u]

            for (loop_index, vertex), u_value in zip(loop_values, raw_u):
                v_value = max(0.0, min(1.0, vertex.z / max_height))
                uv.data[loop_index].uv = (u_value, v_value)
        else:
            radius = top_radius if polygon.index == top_face_index else bottom_radius
            for loop_index in polygon.loop_indices:
                vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co
                uv.data[loop_index].uv = (
                    vertex.x / (radius * 2.0) + 0.5,
                    vertex.y / (radius * 2.0) + 0.5,
                )
    obj = bpy.data.objects.new(name, mesh)
    TEMPLATES.objects.link(obj)
    obj.data.materials.append(piece_wood)
    obj.data.materials.append(piece_face)
    obj.data.polygons[-1].material_index = 1
    for face in obj.data.polygons:
        face.use_smooth = True
    return obj


piece_specs = {
    "black": [("rook", "車"), ("horse", "馬"), ("elephant", "象"), ("advisor", "士"), ("general", "將"), ("cannon", "炮"), ("soldier", "卒")],
    "red": [("rook", "車"), ("horse", "馬"), ("elephant", "相"), ("advisor", "仕"), ("general", "帥"), ("cannon", "炮"), ("soldier", "兵")],
}
piece_names = {}
for side, entries in piece_specs.items():
    for role, glyph in entries:
        name = "Piece_%s_%s" % (side.capitalize(), role.capitalize())
        body = piece_mesh(name)
        parts = [body]
        ink = red_ink if side == "red" else black_ink
        enamel = lettering(name + "_flat_character", glyph, (0, 0, 0.010030), 0.024, ink, TEMPLATES, extrude=0.0, outline=0.00015, bevel_depth=0.0)
        glyph_radius = max(math.hypot(v.co.x, v.co.y) for v in enamel.data.vertices)
        glyph_scale = min(1.0, 0.0098 / glyph_radius)
        enamel.scale.x = glyph_scale
        enamel.scale.y = glyph_scale
        parts.append(enamel)
        circle_vertices = [(radius * math.cos(math.tau * j / 128), radius * math.sin(math.tau * j / 128), 0.010025) for radius in (0.01195, 0.01235) for j in range(128)]
        circle_faces = [(j, j + 128, (j + 1) % 128 + 128, (j + 1) % 128) for j in range(128)]
        circle_mesh = bpy.data.meshes.new(name + "_flat_circle")
        circle_mesh.from_pydata(circle_vertices, [], circle_faces)
        circle_mesh.update()
        circle_mesh.materials.append(ink)
        circle = bpy.data.objects.new(name + "_flat_circle", circle_mesh)
        TEMPLATES.objects.link(circle)
        parts.append(circle)
        bpy.ops.object.select_all(action="DESELECT")
        for part in parts:
            part.select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.join()
        for vertex in body.data.vertices:
            vertex.co.x *= 1.125
            vertex.co.y *= 1.125
        body.data.validate(verbose=True, clean_customdata=True)
        body.data.update()
        for polygon in body.data.polygons:
            polygon.use_smooth = abs(polygon.normal.z) < 0.97
        triangulate = body.modifiers.new("Stable game mesh triangulation", "TRIANGULATE")
        bpy.ops.object.modifier_apply(modifier=triangulate.name)
        body.data.validate(verbose=True, clean_customdata=True)
        body.data.update()
        body.name = name
        for unused_uv in list(body.data.uv_layers)[1:]:
            body.data.uv_layers.remove(unused_uv)
        body.data.uv_layers.active_index = 0
        body.data.uv_layers[0].active_render = True
        if body.data.uv_layers.active is not None:
            try:
                body.data.calc_tangents(uvmap=body.data.uv_layers.active.name)
            except RuntimeError:
                pass
        body["side"] = side
        body["role"] = role
        body["symbol"] = glyph
        body["diameter_m"] = 0.036
        body["height_m"] = 0.010
        body["marking_style"] = "flat colored character and circle; no engraving"
        body["minimum_glyph_ring_gap_m"] = 0.00241875
        body.hide_render = True
        body.hide_set(True)
        piece_names[(side, role)] = body


def preview_piece(side, role, col, row):
    original = piece_names[(side, role)]
    copy = original.copy()
    copy.data = original.data
    copy.name = "Opening_%s_%s_%d_%d" % (side, role, col, row)
    PREVIEW_PIECES.objects.link(copy)
    copy.hide_render = False
    copy.hide_set(False)
    copy.location = (GRID_X[col], GRID_Y[row], TOP + 0.0002)


back = ["rook", "horse", "elephant", "advisor", "general", "advisor", "elephant", "horse", "rook"]
for col, role in enumerate(back):
    preview_piece("black", role, col, 0)
    preview_piece("red", role, col, 9)
for side, cannon_row, soldier_row in (("black", 2, 3), ("red", 7, 6)):
    for col in (1, 7):
        preview_piece(side, "cannon", col, cannon_row)
    for col in (0, 2, 4, 6, 8):
        preview_piece(side, "soldier", col, soldier_row)


def area_light(name, at, power, size, color):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = power
    data.shape = "DISK"
    data.size = size
    data.color = color
    obj = bpy.data.objects.new(name, data)
    STUDIO.objects.link(obj)
    obj.location = at
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()


area_light("Warm softbox", (-0.35, -0.20, 0.48), 5.5, 0.24, (1.0, 0.96, 0.88))
area_light("Cool fill", (0.36, 0.16, 0.38), 3.2, 0.48, (0.93, 0.96, 1.0))
area_light("Edge glow", (0.1, 0.40, 0.33), 2.4, 0.20, (1.0, 0.78, 0.53))
ground_mat = principled("Studio | charcoal velvet", (0.021, 0.018, 0.014), 0.95)
bevel_box("Studio ground", (0, 0, TOP - 0.007), (3.0, 3.0, 0.002), ground_mat, 0, target=STUDIO)
camera_data = bpy.data.cameras.new("Three-quarter product camera")
camera = bpy.data.objects.new("Three-quarter product camera", camera_data)
STUDIO.objects.link(camera)
camera.location = (0.0, -0.62, 0.72)
camera.rotation_euler = (Vector((0, 0, 0)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera_data.type = "PERSP"
camera_data.lens = 60
scene.camera = camera

save_versions = bpy.context.preferences.filepaths.save_version
bpy.context.preferences.filepaths.save_version = 0
if not globals().get("BLENDER_MCP_EXECUTION", False):
    bpy.ops.render.render(write_still=False)
    bpy.data.images["Render Result"].save_render(filepath=PREVIEW.as_posix(), scene=scene)


def export_collection(source, filename, reveal_templates=False):
    bpy.ops.object.select_all(action="DESELECT")
    export_objects = list(source.objects)
    temporary = []
    if source == BOARD:
        depsgraph = bpy.context.evaluated_depsgraph_get()
        for obj in source.objects:
            if obj.type != "MESH":
                continue
            evaluated_mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph), depsgraph=depsgraph)
            copy = bpy.data.objects.new("GameBoardPart", evaluated_mesh)
            scene.collection.objects.link(copy)
            copy.matrix_world = obj.matrix_world.copy()
            temporary.append(copy)
            copy.select_set(True)
        bpy.context.view_layer.objects.active = temporary[0]
        bpy.ops.object.join()
        combined = bpy.context.view_layer.objects.active
        combined.name = "ChessBoard_RedSandalwood"
        combined['grid_x_m'] = GRID_X.tolist()
        combined['grid_y_m'] = GRID_Y.tolist()
        combined['surface_mapping'] = 'single affine planar UV projection'
        temporary = [combined]
        export_objects = temporary
    for obj in export_objects:
        if obj.type == "MESH":
            obj.hide_render = False
            obj.hide_set(False)
            obj.select_set(True)
    final_path = MODELS / filename
    temporary_path = MODELS / (final_path.stem + "_build_" + uuid.uuid4().hex + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=temporary_path.as_posix(),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_extras=True,
    )
    os.replace(temporary_path.as_posix(), final_path.as_posix())
    for obj in temporary:
        bpy.data.objects.remove(obj, do_unlink=True)
    if reveal_templates:
        for obj in source.objects:
            obj.hide_render = True
            obj.hide_set(True)


export_collection(BOARD, "chess_board.glb")
export_collection(TEMPLATES, "chess_pieces.glb", True)
bpy.ops.object.select_all(action="DESELECT")
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.region_3d.view_perspective = "CAMERA"
            area.spaces.active.shading.type = "MATERIAL"
temporary_blend = ROOT / ('XBD_Set_build_' + uuid.uuid4().hex + '.blend')
bpy.ops.wm.save_as_mainfile(filepath=temporary_blend.as_posix(), copy=True)
os.replace(temporary_blend, BLEND)
bpy.context.preferences.filepaths.save_version = save_versions
print("OUTPUT_BLEND", BLEND)
print("OUTPUT_PREVIEW", PREVIEW)
print("OUTPUT_BOARD_GLB", MODELS / "chess_board.glb")
print("OUTPUT_PIECES_GLB", MODELS / "chess_pieces.glb")
print("BOARD_OBJECTS", len(BOARD.objects), "TEMPLATES", len(TEMPLATES.objects), "PREVIEW_PIECES", len(PREVIEW_PIECES.objects))
print("MCP_MODEL_BUILD_PASS")
