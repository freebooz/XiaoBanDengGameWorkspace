"""Build the editable xiangqi set and Godot glTF assets from a blank Blender scene."""

import math
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
BOARD_IMAGE = ASSETS / "bamboo_woodgrain.png"
FRAME_IMAGE = ASSETS / "red_sandalwood_woodgrain.png"
PIECE_IMAGE = ASSETS / "golden_nanmu_fine.png"
FONT_FILE = Path("C:/Windows/Fonts/simkai.ttf")

CELL = 0.050
TOP = 0.020
BOARD_W = 0.530
BOARD_H = 0.580

existing_opening = bpy.data.collections.get("03 | Opening arrangement preview")
if bpy.data.filepath and Path(bpy.data.filepath).name == BLEND.name and existing_opening and len(existing_opening.objects) == 32:
    if bpy.data.objects.get("Frame | continuous red sandalwood rim"):
        bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "XBD_ChineseChess_RedSandalwood_Archive.blend"), copy=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "XBD_ChineseChess_BeforeFlushCorrection.blend"), copy=True)

for obj in tuple(bpy.data.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
for old_collection in tuple(bpy.data.collections):
    bpy.data.collections.remove(old_collection)
for old_material in tuple(bpy.data.materials):
    bpy.data.materials.remove(old_material)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1400
scene.render.resolution_y = 1400
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.render.filepath = str(PREVIEW)
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


BOARD = collection("01 | Engraved bamboo board")
TEMPLATES = collection("02 | Fourteen piece masters (32 mm x 10 mm)")
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


wood = principled("Board | natural satin bamboo", (0.65, 0.43, 0.18), 0.46, 0, 0.10)
if BOARD_IMAGE.exists():
    texture = wood.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = bpy.data.images.load(str(BOARD_IMAGE), check_existing=True)
    texture.image.pack()
    shader = next(node for node in wood.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    wood.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])

edge_wood = principled("Board | carved red sandalwood frame", (0.30, 0.068, 0.038), 0.30, 0, 0.28)
if FRAME_IMAGE.exists():
    texture = edge_wood.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = bpy.data.images.load(str(FRAME_IMAGE), check_existing=True)
    texture.image.pack()
    shader = next(node for node in edge_wood.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    edge_wood.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
relief = principled("Board | polished red sandalwood relief", (0.17, 0.032, 0.016), 0.31, 0.0, 0.26)
gold_detail = principled("Carving | antique golden nanmu corner inlays", (0.43, 0.23, 0.07), 0.31, 0.10, 0.12)
shade = principled("Board | incised near-black lines", (0.065, 0.025, 0.016), 0.7)
piece_wood = principled("Pieces | golden nanmu woodgrain", (0.92, 0.57, 0.15), 0.14, 0, 0.60)
if PIECE_IMAGE.exists():
    texture = piece_wood.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = bpy.data.images.load(str(PIECE_IMAGE), check_existing=True)
    texture.image.pack()
    shader = next(node for node in piece_wood.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    piece_wood.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
piece_face = principled("Pieces | golden nanmu wood face", (0.84, 0.52, 0.16), 0.18, 0, 0.50)
if PIECE_IMAGE.exists():
    texture = piece_face.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = bpy.data.images.load(str(PIECE_IMAGE), check_existing=True)
    texture.image.pack()
    shader = next(node for node in piece_face.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    piece_face.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
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
    (ROOT / "build_progress.txt").write_text("Carving: " + label, encoding="utf-8")
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


# The latest reference is one low bamboo board. The underside arch is cut from
# the same solid mesh, leaving two continuous supporting rails at the sides.
playfield = bevel_box("Board | bamboo slab with integral feet", (0, 0, TOP - 0.012), (0.460, 0.510, 0.024), wood, 0.0008)
underside_cutter = bevel_box("Cut | arched underside clearance", (0, 0, -0.004), (0.390, 0.560, 0.012), shade, 0.004, segments=8)
carve(playfield, [underside_cutter], "Integral curved foot opening")
for polygon in playfield.data.polygons:
    for loop_index in polygon.loop_indices:
        vertex = playfield.data.vertices[playfield.data.loops[loop_index].vertex_index].co
        playfield.data.uv_layers.active.data[loop_index].uv = (vertex.x / 0.460 + 0.5, vertex.y / 0.510 + 0.5)

# Standard 9 x 10 xiangqi intersections. Inner files stop at the river.
for row in range(10):
    y = (4.5 - row) * CELL
    tube("Grid | rank %02d" % row, [(-0.2, y, TOP + 0.0008), (0.2, y, TOP + 0.0008)], 0.00125, shade)
for col in range(9):
    x = (col - 4) * CELL
    spans = [(-0.225, 0.225)] if col in (0, 8) else [(-0.225, -0.025), (0.025, 0.225)]
    for part, (a, b) in enumerate(spans):
        tube("Grid | file %02d / %d" % (col, part), [(x, a, TOP + 0.0008), (x, b, TOP + 0.0008)], 0.00125, shade)
for palace_y in (-0.175, 0.175):
    for sign in (-1, 1):
        tube("Palace | %s / %s" % (palace_y, sign), [(-0.05, palace_y - sign * 0.05, TOP + 0.00082), (0.05, palace_y + sign * 0.05, TOP + 0.00082)], 0.00125, shade)

# Incised target brackets at cannon and soldier posts, with no mark outside the board.
for row in (2, 7):
    for col in (1, 7):
        x, y = (col - 4) * CELL, (4.5 - row) * CELL
        for sx in (-1, 1):
            for sy in (-1, 1):
                a = (x + sx * 0.004, y + sy * 0.004, TOP + 0.00085)
                b = (x + sx * 0.009, y + sy * 0.004, TOP + 0.00085)
                c = (x + sx * 0.004, y + sy * 0.009, TOP + 0.00085)
                tube("Cannon post | %d %d %d %d" % (row, col, sx, sy), [b, a, c], 0.0010, shade)
for row in (3, 6):
    for col in (0, 2, 4, 6, 8):
        x, y = (col - 4) * CELL, (4.5 - row) * CELL
        for sx in (-1, 1):
            if col == 0 and sx < 0 or col == 8 and sx > 0:
                continue
            for sy in (-1, 1):
                a = (x + sx * 0.004, y + sy * 0.004, TOP + 0.00085)
                tube("Soldier post | %d %d %d %d" % (row, col, sx, sy), [(a[0] + sx * 0.004, a[1], a[2]), a, (a[0], a[1] + sy * 0.004, a[2])], 0.0010, shade)

for river_name, text, x in (("Chu He", "楚 河", -0.112), ("Han Jie", "漢 界", 0.112)):
    cutter = lettering("Cut | River " + river_name, text, (x, 0, TOP), 0.025, shade, extrude=0.0004, outline=0.0, bevel_depth=0.0)
    carve(playfield, [cutter], "Engraved river calligraphy")
    lettering("River | " + river_name, text, (x, 0, TOP - 0.00033), 0.025, shade, extrude=0.0, outline=0.0, bevel_depth=0.0)

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
    uv = mesh.uv_layers.new(name="Nanmu flowing grain")
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv = (vertex.x / 0.032 + 0.5, vertex.y / 0.032 + 0.5 + vertex.z * 16)
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
        body.data.validate(verbose=True, clean_customdata=True)
        body.data.update()
        for polygon in body.data.polygons:
            polygon.use_smooth = abs(polygon.normal.z) < 0.97
        triangulate = body.modifiers.new("Stable game mesh triangulation", "TRIANGULATE")
        bpy.ops.object.modifier_apply(modifier=triangulate.name)
        body.data.validate(verbose=True, clean_customdata=True)
        body.data.update()
        body.name = name
        body["side"] = side
        body["role"] = role
        body["symbol"] = glyph
        body["diameter_m"] = 0.032
        body["height_m"] = 0.010
        body["marking_style"] = "flat colored character and circle; no engraving"
        body["minimum_glyph_ring_gap_m"] = 0.00215
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
    copy.location = ((col - 4) * CELL, (4.5 - row) * CELL, TOP + 0.0002)


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
bevel_box("Studio ground", (0, 0, -0.005), (3.0, 3.0, 0.002), ground_mat, 0, target=STUDIO)
camera_data = bpy.data.cameras.new("Three-quarter product camera")
camera = bpy.data.objects.new("Three-quarter product camera", camera_data)
STUDIO.objects.link(camera)
camera.location = (0.0, -0.58, 0.62)
camera.rotation_euler = (Vector((0, 0, 0)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera_data.type = "PERSP"
camera_data.lens = 60
scene.camera = camera

bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
bpy.ops.render.render(write_still=True)


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
        combined.name = "ChessBoard_Bamboo"
        temporary = [combined]
        export_objects = temporary
    for obj in export_objects:
        if obj.type == "MESH":
            obj.hide_render = False
            obj.hide_set(False)
            obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=str(MODELS / filename),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_extras=True,
    )
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
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print("OUTPUT_BLEND", BLEND)
print("OUTPUT_PREVIEW", PREVIEW)
print("OUTPUT_BOARD_GLB", MODELS / "chess_board.glb")
print("OUTPUT_PIECES_GLB", MODELS / "chess_pieces.glb")
print("BOARD_OBJECTS", len(BOARD.objects), "TEMPLATES", len(TEMPLATES.objects), "PREVIEW_PIECES", len(PREVIEW_PIECES.objects))
(ROOT / "build_progress.txt").write_text("Completed: saved Blender model, preview and GLB exports", encoding="utf-8")
