"""Independent tests of the actual saved mesh, image, UV and lacquer finish."""
import bpy
import bmesh
import hashlib
import math
from pathlib import Path
from mathutils import Vector

field = bpy.data.objects['Board | red sandalwood flat plate']
points = [field.matrix_world @ v.co for v in field.data.vertices]
lo = Vector(tuple(min(p[i] for p in points) for i in range(3)))
hi = Vector(tuple(max(p[i] for p in points) for i in range(3)))
assert (hi-lo-Vector((.412,.452,.006))).length < 1e-6, (lo,hi)
for x in (lo.x+.005,0,hi.x-.005):
    hit,p,*_ = field.ray_cast(field.matrix_world.inverted() @ Vector((x,0,-.1)),Vector((0,0,1)))
    assert hit and abs((field.matrix_world @ p).z-lo.z)<1e-6, 'flat underside required'
clearances = [-.160-.018-lo.x,hi.x-.160-.018,-.180-.018-lo.y,hi.y-.180-.018]
assert max(clearances)-min(clearances)<1e-6 and min(clearances)>.02799, clearances
radius=.006
corner_errors=[]
for sx in (-1,1):
    for sy in (-1,1):
        corner=[p for p in points if abs(p.z-hi.z)<1e-6 and sx*p.x>.206-radius-.000001 and sy*p.y>.226-radius-.000001]
        assert len(corner)>=8, ('corner subdivision missing',sx,sy,len(corner))
        errors=[abs(math.hypot(.206-sx*p.x-radius,.226-sy*p.y-radius)-radius) for p in corner]
        assert max(errors)<2e-6, ('corner must be a convex circular arc without protruding strips',errors)
        corner_errors.append(max(errors))
mesh=bmesh.new(); mesh.from_mesh(field.data)
assert all(e.is_manifold for e in mesh.edges), 'board must remain a single closed solid'
mesh.free()
xs, ys = list(field['grid_x_m']), list(field['grid_y_m'])
assert len(xs)==9 and len(ys)==10
samples = [('rank',(xs[6]+xs[7])/2,ys[4],.00060),('file',xs[6],(ys[1]+ys[2])/2,.00060),('palace',xs[3]*.75+xs[5]*.25,ys[0]*.75+ys[2]*.25,.00060),('marker',xs[1]+.0042,ys[2]+.0032,.00050)]
for label,x,y,depth in samples:
    hit,p,*_=field.ray_cast(field.matrix_world.inverted() @ Vector((x,y,.1)),Vector((0,0,-1)))
    assert hit and hi.z-(field.matrix_world @ p).z>=depth, (label,hi.z-(field.matrix_world @ p).z)
image_nodes=[n for n in field.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE']
surface=image_nodes[0].image
assert tuple(surface.size)==(1254,1254), surface.size[:]
source=Path(__file__).resolve().parents[3]/'client/games/chinese_chess/assets/board_reference_surface.png'
assert hashlib.sha256(surface.packed_file.data).digest()==hashlib.sha256(source.read_bytes()).digest(), 'packed image must be the exact latest reference'
side_images=[n.image for n in field.data.materials[1].node_tree.nodes if n.type=='TEX_IMAGE']
assert side_images==[surface], 'sides and corners must use the same reference wood texture'
for face in field.data.polygons:
    if face.material_index==1 and abs(face.normal.z)<.5:
        us=[field.data.uv_layers.active.data[i].uv.x for i in face.loop_indices]
        assert max(us)-min(us)<.4, ('side UV must not wrap across a corner',face.index,us)
exec(compile((Path(__file__).parent/'audit_board_uv.py').read_text(encoding='utf-8-sig'),str(Path(__file__).parent/'audit_board_uv.py'),'exec'))
for material in field.data.materials[:2]:
    shader=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    assert .19 <= shader.inputs['Coat Weight'].default_value <= .21 and .23 <= shader.inputs['Coat Roughness'].default_value <= .25
masters=bpy.data.collections['02 | Fourteen piece masters (36 mm x 10 mm)']
assert len(masters.objects)==14
for obj in masters.objects:
    assert len(obj.data.uv_layers)==1 and obj.data.uv_layers.active.name=='UV0_Nanmu'
    uv=obj.data.uv_layers.active.data
    for face in obj.data.polygons:
        if 'golden nanmu' not in obj.data.materials[face.material_index].name:
            continue
        uvs=[uv[i].uv for i in face.loop_indices]
        twice_area=sum(a.x*b.y-b.x*a.y for a,b in zip(uvs,uvs[1:]+uvs[:1]))
        assert abs(twice_area)>1e-12, ('degenerate wood UV',obj.name,face.index)
for name in ('Pieces | golden nanmu woodgrain','Pieces | golden nanmu wood face'):
    mat=bpy.data.materials[name]
    shader=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    assert shader.inputs['Coat Weight'].default_value>=.54
    assert shader.inputs['Coat Roughness'].default_value<=.13
    normal=next(n for n in mat.node_tree.nodes if n.type=='NORMAL_MAP')
    assert normal.inputs['Strength'].default_value<=.13 and normal.uv_map=='UV0_Nanmu'
print('LATEST_VISUAL_CONTRACT_PASS margins_mm=',[round(v*1000,3) for v in clearances], 'corner_radius_mm=6 corner_error_m=',corner_errors)
