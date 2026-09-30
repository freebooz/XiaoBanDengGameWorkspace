"""Independent validation after opening the saved Blender file in a fresh process."""
import json
import math
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parent
WORKSPACE = ROOT.parents[2]
checks = {}

def require(name, passed, detail):
    checks[name] = {"passed": bool(passed), "detail": detail}
    if not passed:
        raise AssertionError(f"{name}: {detail}")

require("saved_scene_opened", Path(bpy.data.filepath).name == "XBD_ChineseChess_Set.blend", bpy.data.filepath)
board = bpy.data.collections.get("01 | Engraved bamboo board")
masters = bpy.data.collections.get("02 | Fourteen piece masters (32 mm x 10 mm)")
opening = bpy.data.collections.get("03 | Opening arrangement preview")
require("editable_board", board is not None and len(board.objects) > 50, len(board.objects) if board else 0)
require("14_distinct_piece_masters", masters is not None and len(masters.objects) == 14, len(masters.objects) if masters else 0)
require("32_opening_pieces", opening is not None and len(opening.objects) == 32, len(opening.objects) if opening else 0)
require("red_black_16_each", sum(o.get("side") == "red" for o in opening.objects) == 16 and sum(o.get("side") == "black" for o in opening.objects) == 16, {s:sum(o.get("side") == s for o in opening.objects) for s in ("red", "black")})
require("standard_playfield_ranks", len([o for o in board.objects if o.name.startswith("Inlay | Grid | rank")]) == 10, "10 recessed rank lines")
require("river_and_palaces", all(bpy.data.objects.get(name) for name in ("River | Chu He", "River | Han Jie")) and len([o for o in board.objects if o.name.startswith("Inlay | Palace |")]) == 4, "2 river legends and 4 recessed palace diagonals")
require("single_bamboo_body", bpy.data.objects.get("Board | bamboo slab with integral feet") is not None and bpy.data.objects.get("Frame | continuous red sandalwood rim") is None, "one flat bamboo body with integral supports")

piece_dimensions = {}
for obj in masters.objects:
    dims = list(obj.dimensions)
    piece_dimensions[obj.name] = [round(v, 6) for v in dims]
    require("size_" + obj.name, abs(dims[0] - 0.032) < 0.0002 and abs(dims[1] - 0.032) < 0.0002 and 0.0095 <= dims[2] <= 0.011, piece_dimensions[obj.name])
    require("glyph_" + obj.name, len(obj.data.materials) >= 3 and obj.get("symbol") is not None, obj.get("symbol"))
    require("hidden_master_" + obj.name, obj.hide_render, "masters do not overlap the board preview")
    printed = [p for p in obj.data.polygons if "side |" in obj.data.materials[p.material_index].name]
    ink_vertices = [obj.data.vertices[index].co for p in printed for index in p.vertices]
    require("flat_character_and_circle_" + obj.name, bool(ink_vertices) and min(v.z for v in ink_vertices) >= 0.00999 and max(v.z for v in ink_vertices) < 0.0101, "flat ink marking, no engraved lettering or circle")
    glyph_radius = max(math.hypot(v.x, v.y) for v in ink_vertices if math.hypot(v.x, v.y) < 0.0105)
    require("character_circle_margin_" + obj.name, 0.01195 - glyph_radius >= 0.0020, {"minimum_radial_gap_m": 0.01195 - glyph_radius})
    hit, point, normal, polygon_index = obj.ray_cast(Vector((0.01215, 0, 0.1)), Vector((0, 0, -1)))
    require("no_circle_cavity_" + obj.name, hit and point.z >= 0.00999, {"hit_z_m": point.z})
    mesh_copy = obj.data.copy()
    require("valid_mesh_" + obj.name, not mesh_copy.validate(verbose=True), "mesh passes Blender structural validation")
    bpy.data.meshes.remove(mesh_copy)

all_points = [obj.matrix_world @ Vector(corner) for obj in board.objects for corner in obj.bound_box]
bounds = [[min(p[i] for p in all_points), max(p[i] for p in all_points)] for i in range(3)]
require("board_dimensions", 0.36 < bounds[0][1] - bounds[0][0] < 0.38 and 0.40 < bounds[1][1] - bounds[1][0] < 0.42, bounds)
field = bpy.data.objects["Board | bamboo slab with integral feet"]
field_top = max((field.matrix_world @ Vector(p)).z for p in field.bound_box)
underside_heights = []
for x in (0.0, 0.174):
    hit, p, normal, face_index = field.ray_cast(field.matrix_world.inverted() @ Vector((x, 0, -0.1)), Vector((0, 0, 1)))
    require("underside_hit_" + str(x), hit, x)
    underside_heights.append((field.matrix_world @ p).z)
require("curved_underside_support", underside_heights[0] - underside_heights[1] > 0.0045, underside_heights)
minimum_gap = 1.0
for obj in opening.objects:
    for corner in obj.bound_box:
        p = obj.matrix_world @ Vector(corner)
        minimum_gap = min(minimum_gap, 0.184 - abs(p.x), 0.204 - abs(p.y))
require("pieces_clear_of_board_edge", minimum_gap >= 0.0075, {"minimum_edge_clearance_m": minimum_gap})
for sample_name, x, y in (("rank", 0.10, 0.02), ("file", 0.08, 0.08), ("palace", 0.02, 0.16), ("cannon_marker", -0.1148, 0.1032)):
    local_start = field.matrix_world.inverted() @ Vector((x, y, 0.1))
    hit, point, normal, polygon_index = field.ray_cast(local_start, Vector((0, 0, -1)))
    world_point = field.matrix_world @ point
    require("true_grid_cavity_" + sample_name, hit and world_point.z < field_top - 0.00060, {"depth_m": field_top - world_point.z})
for label, mat_name, image_name in (("bamboo", "Board | natural satin bamboo", "bamboo_woodgrain.png"), ("golden_nanmu", "Pieces | golden nanmu woodgrain", "golden_nanmu_fine.png")):
    mat = bpy.data.materials.get(mat_name)
    images = [n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image] if mat else []
    require(label + "_packed_texture", any(im.name.startswith(image_name) and im.packed_file for im in images), [im.name for im in images])

require("preview_render", (ROOT / "XBD_ChineseChess_Set_preview.png").stat().st_size > 100_000, "PNG render saved")
for filename in ("chess_board.glb", "chess_pieces.glb"):
    path = WORKSPACE / "client/games/chinese_chess/assets/models" / filename
    require(filename + "_exists", path.exists() and path.stat().st_size > 50_000, str(path))

report = {"status": "PASS", "blender_version": bpy.app.version_string, "board_bounds_m": bounds, "piece_dimensions_m": piece_dimensions, "checks": checks}
(ROOT / "validation_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print("SAVED_BLEND_VALIDATION_PASS", len(checks))
