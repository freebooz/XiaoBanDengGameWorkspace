import json
import bpy

names = ["Board | solid carved base", "Board | golden top playfield", "Frame | continuous red sandalwood rim", "Opening_red_rook_0_9", "Three-quarter product camera"]
print(json.dumps({"filepath": bpy.data.filepath, "dirty": bpy.data.is_dirty, "objects": [{"name": name, "location": list(bpy.data.objects[name].location), "dimensions": list(bpy.data.objects[name].dimensions)} for name in names if name in bpy.data.objects]}, ensure_ascii=False))
