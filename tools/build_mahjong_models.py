"""Blender headless import of the user's Unreal Mahjong table and reusable 3D tile.

Run with: blender -b --factory-startup --python tools/build_mahjong_models.py
The Unreal source tree is read-only. The editable .blend and runtime .glb files go to
client/games/mahjong/guiyang/assets/models/.
"""

import hashlib
import json
from pathlib import Path

import bpy


WORKSPACE = Path(__file__).resolve().parents[1]
SOURCE = Path(r"E:\work\Game\MahjongGame\SourceArt\3D\MahjongTableProduction")
OUTPUT = WORKSPACE / "client/games/mahjong/guiyang/assets/models"
OUTPUT.mkdir(parents=True, exist_ok=True)
EDITABLE = WORKSPACE / "artifacts/mahjong_models"
EDITABLE.mkdir(parents=True, exist_ok=True)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for block in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def principled_material(name, color, roughness, metallic=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return material


def set_table_material(material, family, roughness, metallic):
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    links = material.node_tree.links
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = bpy.data.images.load(str(SOURCE / "Textures" / f"{family}_BaseColor_2K.png"), check_existing=True)
    texture.image.scale(1024, 1024)
    texture.image.pack()
    links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    normal = nodes.new("ShaderNodeTexImage")
    normal.image = bpy.data.images.load(str(SOURCE / "Textures" / f"{family}_Normal_2K.png"), check_existing=True)
    normal.image.colorspace_settings.name = "Non-Color"
    normal.image.scale(1024, 1024)
    normal.image.pack()
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = 0.45 if "Felt" in family else 0.32
    links.new(normal.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])


def export_table():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    source_glb = SOURCE / "SM_StandardMahjongTable.glb"
    bpy.ops.import_scene.gltf(filepath=str(source_glb))
    # The source export contains a stray 2-metre cube that would hide the table.
    for obj in list(bpy.data.objects):
        if obj.type == "MESH" and obj.name == "Cube":
            bpy.data.objects.remove(obj, do_unlink=True)
    families = {
        "M_Table_Felt_Green_PBR": ("T_TableFeltDeepForest", 0.68, 0.0),
        "M_Table_Frame_BlackAlloy": ("T_TableFrameBlackBronze", 0.32, 0.62),
        "M_Table_Frame_GoldInlay": ("T_TableGold", 0.29, 0.7),
        "M_Table_Controller_Gunmetal": ("T_TableControllerGunmetal", 0.33, 0.7),
        "M_Table_Controller_BlackPanel": ("T_TableControllerBlack", 0.26, 0.28),
        "M_Table_Controller_GoldLabel": ("T_TableGold", 0.28, 0.72),
        "M_Table_Controller_DirectionGold": ("T_TableGold", 0.28, 0.72),
        "M_Table_Controller_SectorDividerGold": ("T_TableGold", 0.28, 0.72),
    }
    for name, (family, roughness, metallic) in families.items():
        material = bpy.data.materials.get(name)
        if material is not None:
            set_table_material(material, family, roughness, metallic)
    glass = bpy.data.materials.get("M_Table_Controller_TransparentGlass")
    if glass:
        glass.use_nodes = True
        bsdf = glass.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (0.06, 0.13, 0.14, 1)
            bsdf.inputs["Roughness"].default_value = 0.15
            bsdf.inputs["Transmission Weight"].default_value = 0.18
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(EDITABLE / "mahjong_table.blend"))
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT / "mahjong_table.glb"), export_format="GLB", export_apply=True)
    return len([obj for obj in bpy.data.objects if obj.type == "MESH"])


def beveled_box(name, dimensions, location, material, bevel):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    modifier = obj.modifiers.new("Soft moulded edges", "BEVEL")
    modifier.width = bevel
    modifier.segments = 4
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def export_tile():
    # Keep this legacy full-table command on the same canonical real tile pipeline.
    import runpy
    runpy.run_path(str(WORKSPACE / "tools/import_real_mahjong_tile.py"), run_name="__main__")
    return 2


table_meshes = export_table()
tile_meshes = export_tile()
manifest = json.loads((OUTPUT / "model_manifest.json").read_text(encoding="utf-8"))
manifest.update({
    "source_table": str(SOURCE / "SM_StandardMahjongTable.glb"),
    "source_table_sha256": sha256(SOURCE / "SM_StandardMahjongTable.glb"),
    "table_meshes": table_meshes,
    "tile_meshes": tile_meshes,
    "files": {path.name: {"bytes": path.stat().st_size, "sha256": sha256(path)} for path in list(OUTPUT.glob("*.glb")) + list(EDITABLE.glob("*.blend"))},
})
(OUTPUT / "model_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding="utf-8",newline='\n')
print("MAHJONG_MODEL_IMPORT_OK", manifest["files"])
