"""Run inside the source Unreal editor to export the licensed Mahjong50 master mesh.

This script only reads Unreal assets and writes FBX/PNG into the XiaoBanDeng
workspace. It does not save or modify the source project's packages.
"""

from pathlib import Path
import unreal


out = Path(r"E:\work\2026\XiaoBanDengGameWorkspace\artifacts\mahjong_models\unreal_export")
out.mkdir(parents=True, exist_ok=True)

mesh = unreal.load_asset("/Game/Art/Mahjong/Mahjong50/Meshes/SM_Mahjong50")
if mesh is None:
    raise RuntimeError("SM_Mahjong50 could not be loaded")
task = unreal.AssetExportTask()
task.object = mesh
task.filename = str(out / "SM_Mahjong50.fbx")
task.exporter = unreal.StaticMeshExporterFBX()
task.automated = True
task.prompt = False
task.replace_identical = True
if not unreal.Exporter.run_asset_export_task(task):
    raise RuntimeError("Unreal FBX export failed")

for name in ("T_Mahjong50_Ivory_BaseColor", "T_Mahjong50_GreenWrap_BaseColor", "T_Mahjong50_FaceAtlas_BaseColor"):
    texture = unreal.load_asset(f"/Game/Art/Mahjong/Mahjong50/Textures/{name}")
    if texture is None:
        raise RuntimeError(f"Missing {name}")
    texture_task = unreal.AssetExportTask()
    texture_task.object = texture
    texture_task.filename = str(out / f"{name}.png")
    texture_task.exporter = unreal.TextureExporterPNG()
    texture_task.automated = True
    texture_task.prompt = False
    texture_task.replace_identical = True
    if not unreal.Exporter.run_asset_export_task(texture_task):
        raise RuntimeError(f"Could not export {name}")

print("MAHJONG50_UNREAL_EXPORT_OK", str(out))
