import bpy
import bmesh
import json
from mathutils import Vector

source = bpy.data.objects["Board | bamboo slab with integral feet"]
results = []
for kind in ("box", "tube", "welded_tube"):
    if kind == "box":
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0.0, 0.02, 0.0199))
        cutter = bpy.context.object
        cutter.dimensions = (0.12, 0.0006, 0.0006)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    else:
        curve = bpy.data.curves.new("diagnostic_tube", "CURVE")
        curve.dimensions = "3D"
        curve.bevel_depth = 0.0003
        curve.bevel_resolution = 2
        curve.use_fill_caps = True
        spline = curve.splines.new("POLY")
        spline.points.add(1)
        spline.points[0].co = (-0.06, 0.02, 0.0199, 1)
        spline.points[1].co = (0.06, 0.02, 0.0199, 1)
        cutter = bpy.data.objects.new("diagnostic_tube", curve)
        bpy.context.scene.collection.objects.link(cutter)
        bpy.ops.object.select_all(action="DESELECT")
        cutter.select_set(True)
        bpy.context.view_layer.objects.active = cutter
        bpy.ops.object.convert(target="MESH")
    bm = bmesh.new()
    bm.from_mesh(cutter.data)
    if kind == "welded_tube":
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.0000001)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(cutter.data)
        cutter.data.update()
    nonmanifold = sum(not edge.is_manifold for edge in bm.edges)
    bm.free()
    for solver in ("MANIFOLD", "EXACT"):
        obj = source.copy()
        obj.data = source.data.copy()
        bpy.context.scene.collection.objects.link(obj)
        obj.modifiers.clear()
        modifier = obj.modifiers.new("diagnostic", "BOOLEAN")
        modifier.solver = solver
        modifier.operation = "DIFFERENCE"
        modifier.object = cutter
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        hit, point, normal, face = obj.ray_cast(obj.matrix_world.inverted() @ Vector((0, 0.02, 0.1)), Vector((0, 0, -1)))
        results.append({"kind": kind, "solver": solver, "cutter_nonmanifold_edges": nonmanifold, "vertices": len(obj.data.vertices), "depth": 0.02 - (obj.matrix_world @ point).z if hit else None})
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.objects.remove(cutter, do_unlink=True)
print(json.dumps(results))
