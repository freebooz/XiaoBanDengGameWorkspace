"""Inspect the saved asset and exported PBR/UV data before changing appearance."""
import bpy
import json
import math
import struct
import numpy as np
from pathlib import Path

root = Path(__file__).resolve().parent
assets = root.parents[2] / "client/games/chinese_chess/assets"
result = {"blend_path": bpy.data.filepath, "objects": {}}
for name in ("Piece_Red_General", "Piece_Black_Rook"):
    obj = bpy.data.objects[name]
    uv = obj.data.uv_layers.active
    wood_polygons = [p for p in obj.data.polygons if p.material_index < 2]
    degenerate = 0
    for p in wood_polygons:
        coords = [uv.data[i].uv for i in p.loop_indices]
        area = abs(sum(coords[i].x * coords[(i+1)%len(coords)].y - coords[(i+1)%len(coords)].x * coords[i].y for i in range(len(coords))) * .5)
        degenerate += area < 1e-10
    result["objects"][name] = {"dimensions": list(obj.dimensions), "uv_layers": [u.name for u in obj.data.uv_layers], "active_uv": uv.name, "wood_polygons": len(wood_polygons), "degenerate_wood_uv": degenerate}
result["materials"] = {}
for mat in bpy.data.materials:
    if not mat.name.startswith("Pieces |"):
        continue
    shader = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    details = {}
    for key in ("Base Color", "Roughness", "Metallic", "Coat Weight", "Coat Roughness", "Normal"):
        socket = shader.inputs[key]
        details[key] = {"linked": socket.is_linked, "source": socket.links[0].from_node.type if socket.is_linked else None, "default": list(socket.default_value) if hasattr(socket.default_value, "__len__") else socket.default_value}
    details["textures"] = []
    for node in mat.node_tree.nodes:
        if node.type != "TEX_IMAGE" or node.image is None:
            continue
        image = node.image
        pixels = np.array(image.pixels[:], dtype=np.float32).reshape(-1, 4)
        details["textures"].append({"name": image.name, "size": list(image.size), "colorspace": image.colorspace_settings.name, "packed": bool(image.packed_file), "uv_source": node.inputs["Vector"].links[0].from_node.type if node.inputs["Vector"].is_linked else "active UV", "rgb_min": pixels[:,:3].min(axis=0).tolist(), "rgb_max": pixels[:,:3].max(axis=0).tolist(), "rgb_std": pixels[:,:3].std(axis=0).tolist()})
    result["materials"][mat.name] = details
blob = (assets / "models/chess_pieces.glb").read_bytes()
json_size = struct.unpack_from("<I", blob, 12)[0]
gltf = json.loads(blob[20:20+json_size])
result["glb_materials"] = gltf.get("materials", [])
result["glb_attributes"] = [{"name": mesh.get("name"), "attributes": [list(p["attributes"]) for p in mesh["primitives"]]} for mesh in gltf["meshes"]]
result["glb_extensions"] = gltf.get("extensionsUsed", [])
(root / "piece_material_audit_before.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"uv": result["objects"], "materials": result["glb_materials"][:2], "extensions": result["glb_extensions"]}, ensure_ascii=False))
