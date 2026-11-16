"""Independently reopen editable .blend assets and imported runtime .glb meshes."""

from pathlib import Path
import json
import struct
import hashlib
import bpy

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "client/game_framework/card3d/assets/models"
CARDS = ROOT / "client/game_framework/card3d/assets/cards"
EDITABLE = ROOT / "SourceAssets/Poker"
report = {}

for stem, required in {
    "poker_card": {"CardBody_63x88x1.3mm", "CardFace", "CardBack"},
    "poker_table": {"SolidWalnutTable", "FeltPlayingSurface", "PolishedWoodRail", "BrassOuterAccent"},
}.items():
    path = EDITABLE / (stem + ".blend")
    bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False)
    names = set(bpy.data.objects.keys())
    assert required <= names, (stem, required - names)
    if stem == "poker_card":
        body = bpy.data.objects["CardBody_63x88x1.3mm"]
        assert all(abs(actual - expected) < 0.0001 for actual, expected in zip(body.dimensions, (0.063, 0.088, 0.0013)))
        assert len(body.data.vertices) > 8
        assert bpy.data.objects["CardFace"].data.uv_layers
        assert bpy.data.objects["CardBack"].data.uv_layers
    report[stem + "_blend"] = {"mesh_count": sum(obj.type == "MESH" for obj in bpy.data.objects), "bytes": path.stat().st_size}

    bpy.ops.wm.read_factory_settings(use_empty=True)
    glb = MODELS / (stem + ".glb")
    bpy.ops.import_scene.gltf(filepath=str(glb))
    imported = set(bpy.data.objects.keys())
    assert required <= imported, (stem, required - imported)
    report[stem + "_glb"] = {"mesh_count": sum(obj.type == "MESH" for obj in bpy.data.objects), "bytes": glb.stat().st_size, "sha256": hashlib.sha256(glb.read_bytes()).hexdigest()}

png_files = list(CARDS.glob("*.png"))
assert len(png_files) == 55, len(png_files)
for file in png_files:
    data = file.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    assert struct.unpack(">II", data[16:24]) == (378, 528), file
report["textures"] = {"count": len(png_files), "size": [378, 528]}
(EDITABLE / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print("POKER_MODEL_VALIDATION_OK", json.dumps(report, ensure_ascii=False))
