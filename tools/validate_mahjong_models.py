"""Independently reopen editable and exported Mahjong assets in Blender."""

from pathlib import Path
import bpy


ROOT = Path(__file__).resolve().parents[1]
EDITABLE = ROOT / "artifacts/mahjong_models"
RUNTIME = ROOT / "client/games/mahjong/guiyang/assets/models"

for name, minimum_meshes in (("mahjong_table", 15), ("mahjong_tile", 3)):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.open_mainfile(filepath=str(EDITABLE / f"{name}.blend"))
    editable_meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    if len(editable_meshes) < minimum_meshes:
        raise RuntimeError(f"{name}: too few editable meshes: {len(editable_meshes)}")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(RUNTIME / f"{name}.glb"))
    runtime_meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    if len(runtime_meshes) < minimum_meshes:
        raise RuntimeError(f"{name}: too few GLB meshes: {len(runtime_meshes)}")
    if name == "mahjong_table":
        if any(obj.name == "Cube" for obj in runtime_meshes):
            raise RuntimeError("Stray occluding cube survived table export")
        images = list(bpy.data.images)
        print("MAHJONG_TABLE_TEXTURES", [(image.name, image.packed_file is not None) for image in images])
        if len(images) < 5:
            raise RuntimeError("Table PBR textures were not embedded")
    else:
        if not any(obj.name.startswith("TileFace") for obj in runtime_meshes):
            raise RuntimeError("TileFace mesh missing")
    print("MAHJONG_MODEL_REOPEN_OK", name, "editable_meshes", len(editable_meshes), "glb_meshes", len(runtime_meshes))
