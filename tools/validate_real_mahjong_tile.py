"""Independently measure the native 56 mm tile and validate its saved materials."""
from pathlib import Path
import json, hashlib
import bpy, bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / 'client/games/mahjong/guiyang/assets/models'
SOURCE = ROOT / 'SourceAssets/Mahjong/mahjong_tile.blend'

def validate(label):
    meshes=[o for o in bpy.data.objects if o.type=='MESH']
    assert {o.name for o in meshes}=={'TileBody','TileFace'}, (label,'canonical meshes', [o.name for o in meshes])
    points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
    dims=[max(v[i] for v in points)-min(v[i] for v in points) for i in range(3)]
    assert all(abs(a-b)<1e-6 for a,b in zip(dims,(.039,.056,.028))), (label,'actual source dimensions',dims)
    for obj in meshes:
        assert (obj.matrix_world.to_scale() - Vector((1,1,1))).length < 1e-6, (label, 'non-unit mesh scale', obj.name)
    assert abs(min(v.z for v in points))<1e-6, (label,'bottom origin')
    face=bpy.data.objects['TileFace']
    assert len(face.data.polygons)==2 and all(p.normal.z>.999 for p in face.data.polygons), (label,'face-up front')
    uv=face.data.uv_layers.active
    assert uv is not None, (label,'face UV missing')
    normals={}
    for p in face.data.polygons:
        for li in p.loop_indices:
            v=face.data.vertices[face.data.loops[li].vertex_index].co
            key=tuple(round(x,7) for x in v)
            normal=face.data.corner_normals[li].vector
            if key in normals:
                assert (normals[key]-normal).length<2e-4, (label,'diagonal front shading seam',key)
            normals[key]=normal.copy()
            assert abs(uv.data[li].uv.x-(v.x/.034125+.5))<2e-5, (label,'mirrored front U')
            assert abs(uv.data[li].uv.y-(v.y/.05096+.5))<2e-5, (label,'upside-down front V')
    # Independent geometric weld proves front and body close a single shell.
    bm=bmesh.new()
    for o in meshes:
        offset=len(bm.verts)
        verts=[bm.verts.new(o.matrix_world@v.co) for v in o.data.vertices]
        for p in o.data.polygons:
            bm.faces.new([verts[i] for i in p.vertices])
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7)
    assert all(e.is_manifold for e in bm.edges), (label,'open/overlapping shell',sum(not e.is_manifold for e in bm.edges))
    assert bm.calc_volume(signed=True)>0, (label,'inverted shell')
    bm.free()
    body=bpy.data.objects['TileBody']
    colors=body.data.color_attributes.active_color
    assert colors is not None, (label,'green layer mask lost')
    values=[c.color[0] for c in colors.data]
    assert min(values)<.01 and max(values)>.99, (label,'green/ivory mask collapsed',min(values),max(values), colors.name,[(c.name,c.domain,c.data_type) for c in body.data.color_attributes])
    assert len(body.data.polygons)>1000, (label,'rounded source mesh replaced with box')
    print('REAL_MAHJONG_GEOMETRY_OK',label,'dimensions_mm',[round(d*1000,2) for d in dims], 'closed_shell=true')

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(RUNTIME/'mahjong_tile.glb'))
validate('GLB')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
validate('BLEND')
assert bpy.context.scene.get('SourceFBXSHA256'), 'Source provenance missing'
assert bpy.data.objects['TileBody'].data.color_attributes.active_color.name=='GreenLayerMask'
face_material=bpy.data.objects['TileFace'].data.materials[0]
nodes=face_material.node_tree.nodes
assert any(n.type=='NORMAL_MAP' for n in nodes), 'engraving normals missing'
assert any(n.type=='SEPARATE_COLOR' for n in nodes), 'ORM channels missing'
assert sum(n.type=='TEX_IMAGE' and n.image and n.image.packed_file is not None for n in nodes)>=3, 'saved PBR maps not packed'
assert all(n.image.colorspace_settings.name=='Non-Color' for n in nodes if n.type=='TEX_IMAGE' and n.image and ('Normal' in n.image.name or 'ORM' in n.image.name)), 'linear data sampled as sRGB'
index=json.loads((RUNTIME/'textures/mahjong_face_atlas.json').read_text(encoding='utf-8'))
assert len(index['tiles'])==34 and len(set(t['name'] for t in index['tiles']))==34
assert (RUNTIME/'textures/T_Mahjong50_FaceAtlas_BaseColor.png').is_file()
manifest=json.loads((RUNTIME/'model_manifest.json').read_text(encoding='utf-8'))
assert manifest['tile_dimensions_mm'] == [39,56,28] and manifest['tile_dimension_order'] == ['width','height','thickness']
for path in (RUNTIME/'mahjong_tile.glb',ROOT/'artifacts/mahjong_models/mahjong_tile.blend'):
    entry=manifest['files'][path.name]
    assert entry['bytes']==path.stat().st_size and entry['sha256']==hashlib.sha256(path.read_bytes()).hexdigest(), ('stale asset manifest',path.name)
    assert path.name not in manifest, ('duplicate top-level asset manifest',path.name)
print('REAL_MAHJONG_SAVED_PBR_OK face_count=34 shared_atlas=true source_fbx=true')
