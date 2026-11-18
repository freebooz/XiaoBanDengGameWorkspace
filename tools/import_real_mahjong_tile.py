"""Build the native 56 mm tile from the editable Blender asset or its original FBX.

Run with Blender --background --python tools/import_real_mahjong_tile.py.
The source packages and source exports are never modified.
"""
from pathlib import Path
import hashlib, json, math, shutil, sys
import bpy, bmesh
from mathutils import Matrix, Vector

ROOT=Path(__file__).resolve().parents[1]
SOURCE=Path('E:/work/Game/MahjongGame/Saved/Diagnostics/Mahjong50')
EDIT=ROOT/'SourceAssets/Mahjong'
RUNTIME=ROOT/'client/games/mahjong/guiyang/assets/models'
TEXTURES=RUNTIME/'textures'
PREVIEW=ROOT/'artifacts/mahjong_models'
FBX=SOURCE/'SM_Mahjong50_Characters_1.fbx'

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def srgb(c): return c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4
def rgba(hex): return tuple(srgb(int(hex[i:i+2],16)/255) for i in (0,2,4))+(1,)
def principled(name,color,roughness):
    m=bpy.data.materials.new(name); m.use_nodes=True
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value=color
    p.inputs['Roughness'].default_value=roughness
    p.inputs['IOR'].default_value=1.49
    p.inputs['Coat Weight'].default_value=.24
    p.inputs['Coat Roughness'].default_value=.18
    return m,p


def save_native_tile(body, face):
    # Blender axes for the flat tile are width, height, thickness. glTF is Y-up.
    target = Vector((0.039, 0.056, 0.028))
    points = [v.co for v in body.data.vertices]
    size = Vector([max(v[i] for v in points) - min(v[i] for v in points) for i in range(3)])
    if (target - size).length > 1e-7:
        transform = Matrix.Diagonal(Vector([target[i] / size[i] for i in range(3)] + [1.0]))
        normal_transform = transform.to_3x3().inverted().transposed()
        for obj in (body, face):
            mesh = obj.data
            normals = [(normal_transform @ n.vector).normalized() for n in mesh.corner_normals]
            mesh.transform(transform)
            mesh.normals_split_custom_set(normals)
            mesh.update()
    body.data.name = 'Mahjong56_RoundedSolidBody'
    face.data.name = 'Mahjong56_ExistingFrontSurface'
    bpy.context.scene['PhysicalDimensionsMillimeters'] = '39 x 56 x 28 (width x height x thickness)'
    editable = EDIT / 'mahjong_tile.blend'
    exported = RUNTIME / 'mahjong_tile.glb'
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(editable))
    bpy.ops.object.select_all(action='DESELECT')
    body.select_set(True)
    face.select_set(True)
    # Temporarily expose the vertex mask to the exporter. The editable material keeps its resin mix.
    tree = body.data.materials[0].node_tree
    color = next(n for n in tree.nodes if n.type == 'BSDF_PRINCIPLED').inputs['Base Color']
    previous = color.links[0].from_socket
    mask = next(n for n in tree.nodes if n.type == 'VERTEX_COLOR')
    tree.links.new(mask.outputs['Color'], color)
    try:
        bpy.ops.export_scene.gltf(filepath=str(exported), export_format='GLB', use_selection=True,
            export_yup=True, export_tangents=True, export_normals=True, export_materials='EXPORT',
            export_vertex_color='NAME', export_vertex_color_name='GreenLayerMask', export_image_format='AUTO')
    finally:
        tree.links.new(previous, color)
    shutil.copy2(editable, PREVIEW / editable.name)
    path = RUNTIME / 'model_manifest.json'
    manifest = json.loads(path.read_text(encoding='utf-8'))
    manifest.update(tile_dimensions_mm=[39, 56, 28], tile_dimension_order=['width', 'height', 'thickness'],
                    tile_model_note='Native 56 mm rounded resin tile with the original engraved face, UVs and vertex mask.')
    for asset in (editable, exported):
        manifest.setdefault('files', {})[asset.name] = {'bytes': asset.stat().st_size, 'sha256': sha(asset)}
        manifest.pop(asset.name, None)
    path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8', newline='\n')


def main():
    if '--from-blend' in sys.argv or not FBX.is_file():
        bpy.ops.wm.open_mainfile(filepath=str(EDIT / 'mahjong_tile.blend'))
        save_native_tile(bpy.data.objects['TileBody'], bpy.data.objects['TileFace'])
        print('REAL_MAHJONG_NATIVE_56_EXPORT_OK')
        return

    for d in (EDIT,TEXTURES,PREVIEW): d.mkdir(parents=True,exist_ok=True)
    archive=PREVIEW/'before_real_tile_import'
    if not archive.exists():
        archive.mkdir()
        for p in (RUNTIME/'mahjong_tile.glb',PREVIEW/'mahjong_tile.blend',RUNTIME/'model_manifest.json'):
            if p.exists(): shutil.copy2(p,archive/p.name)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.file_preview_type='NONE'
    bpy.ops.import_scene.fbx(filepath=str(FBX))
    ob=next(o for o in bpy.data.objects if o.type=='MESH')
    bpy.context.view_layer.objects.active=ob
    ob.select_set(True)
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    # Standing source +Y face becomes +Z. Center the face-up asset, with bottom Z=0.
    rotation=Matrix.Rotation(math.pi/2,4,'X')
    source_normals=[rotation.to_3x3()@n.vector for n in ob.data.corner_normals]
    for v in ob.data.vertices:
        v.co=rotation@v.co+Vector((0,.025,.013))
    ob.data.normals_split_custom_set(source_normals)
    mask=ob.data.color_attributes[0]
    raw=[c.color_srgb[0] for c in mask.data]
    ob.data.color_attributes.remove(mask)
    mask=ob.data.color_attributes.new(name='GreenLayerMask',type='FLOAT_COLOR',domain='CORNER')
    for c,value in zip(mask.data,raw): c.color=(value,value,value,1)
    ob.data.color_attributes.active_color=mask
    ob.data.color_attributes.render_color_index=0
    # Split just the existing front triangles; no second overlay or duplicated surface.
    bpy.context.tool_settings.mesh_select_mode=(False,False,True)
    for p in ob.data.polygons: p.select=p.material_index==1
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.separate(type='SELECTED')
    bpy.ops.object.mode_set(mode='OBJECT')
    face=next(o for o in bpy.data.objects if o.type=='MESH' and o!=ob)
    ob.name='TileBody'; ob.data.name='Mahjong50_RoundedSolidBody'
    face.name='TileFace'; face.data.name='Mahjong50_ExistingFrontSurface'
    for attr in list(face.data.color_attributes): face.data.color_attributes.remove(attr)
    for mesh in (ob,face):
        for uv in list(mesh.data.uv_layers)[1:]: mesh.data.uv_layers.remove(uv)
        mesh.data.uv_layers[0].name='UVMap'
        # Source split normals were transformed with the geometry; retain the authored
        # broad planar highlights and smooth rounded corner transitions.
        # Keep the source smooth basis on both front triangles. Changing it after
        # assigning custom normals would decode two different normals at shared corners.
        for p in mesh.data.polygons: p.use_smooth=True
        mesh.data.update()
    for p in face.data.polygons:
        for li in p.loop_indices:
            v=face.data.vertices[face.data.loops[li].vertex_index].co
            face.data.uv_layers[0].data[li].uv=((v.x+.01575)/.0315,(v.y+.02275)/.0455)

    body_mat,p=principled('M_Mahjong50_TwoLayerResin',rgba('f7f5e9'),.27)
    nodes=body_mat.node_tree.nodes; links=body_mat.node_tree.links
    col=nodes.new('ShaderNodeVertexColor'); col.layer_name='GreenLayerMask'
    mix=nodes.new('ShaderNodeMixRGB'); mix.inputs[1].default_value=rgba('f7f5e9'); mix.inputs[2].default_value=rgba('176b40')
    links.new(col.outputs['Color'],mix.inputs[0]); links.new(mix.outputs[0],p.inputs['Base Color'])
    noise=nodes.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value=900
    bump=nodes.new('ShaderNodeBump'); bump.inputs['Strength'].default_value=.04; bump.inputs['Distance'].default_value=.000035
    links.new(noise.outputs['Fac'],bump.inputs['Height']); links.new(bump.outputs[0],p.inputs['Normal'])
    ob.data.materials.clear(); ob.data.materials.append(body_mat)
    for poly in ob.data.polygons: poly.material_index=0

    images={}
    for kind in ('BaseColor','Normal','ORM','Height'):
        original=SOURCE/f'T_Mahjong50_FaceAtlas_{kind}.png'
        image=bpy.data.images.load(str(original),check_existing=False)
        image.colorspace_settings.name='sRGB' if kind=='BaseColor' else 'Non-Color'
        # 4K atlas retains 352x512 authored pixels per playable tile; shared by all tiles.
        image.scale(4096,2048)
        image.filepath_raw=str(TEXTURES/original.name); image.file_format='PNG'; image.save(); image.pack()
        images[kind]=image

    face_mat,p=principled('M_Mahjong50_EngravedFaceAtlas',rgba('f7f5e9'),.28)
    nodes=face_mat.node_tree.nodes; links=face_mat.node_tree.links
    uv=nodes.new('ShaderNodeTexCoord')
    mapping=nodes.new('ShaderNodeMapping'); mapping.name='AtlasUV_Mapping'
    mapping.inputs['Scale'].default_value=(704/8192,1024/4096,1)
    # Default preview is five characters. Blender's V goes bottom to top.
    mapping.inputs['Location'].default_value=((160+4*896)/8192,3/4,0)
    links.new(uv.outputs['UV'],mapping.inputs['Vector'])
    samples={}
    for kind in ('BaseColor','Normal','ORM'):
        n=nodes.new('ShaderNodeTexImage'); n.image=images[kind]; n.extension='EXTEND'; n.label=kind
        links.new(mapping.outputs['Vector'],n.inputs['Vector']); samples[kind]=n
    links.new(samples['BaseColor'].outputs['Color'],p.inputs['Base Color'])
    normal=nodes.new('ShaderNodeNormalMap'); normal.inputs['Strength'].default_value=.7
    links.new(samples['Normal'].outputs['Color'],normal.inputs['Color']); links.new(normal.outputs[0],p.inputs['Normal'])
    channels=nodes.new('ShaderNodeSeparateColor'); channels.mode='RGB'
    links.new(samples['ORM'].outputs['Color'],channels.inputs[0]); links.new(channels.outputs['Green'],p.inputs['Roughness'])
    face.data.materials.clear(); face.data.materials.append(face_mat)
    for poly in face.data.polygons: poly.material_index=0

    scene=bpy.context.scene
    scene['SourceFBX']=str(FBX); scene['SourceFBXSHA256']=sha(FBX)
    scene['FaceSurface']='Source triangles, coplanar with original body; no added UI image plane'
    scene['BodyMaterial']='Ivory/green resin mixed by original authored vertex R mask'
    scene['AtlasUV']='704x1024 face; X=160+896*column; top-origin rows Characters,Bamboo,Dots,Honors'
    scene.world=bpy.data.worlds.new('MahjongTileStudioWorld')
    scene.world.use_nodes=True
    scene.world.node_tree.nodes.get('Background').inputs[0].default_value=(.16,.19,.23,1)
    scene.world.node_tree.nodes.get('Background').inputs[1].default_value=.45
    save_native_tile(ob, face)

    tiles=[]
    for row,family in enumerate(('Characters','Bamboo','Dots')):
        for rank in range(1,10): tiles.append({'name':f'{family}_{rank}','column':rank-1,'row_from_top':row})
    for col,name in enumerate(('North','White_Dragon','South','Red_Dragon','Green_Dragon','East','West')):
        tiles.append({'name':name,'column':col,'row_from_top':3})
    (TEXTURES/'mahjong_face_atlas.json').write_text(json.dumps({'size':[4096,2048],'authoring_size':[8192,4096],'cell_stride':[896,1024],'face_region':[160,0,704,1024],'tiles':tiles},indent=2)+'\n',encoding='utf-8',newline='\n')
    manifest=json.loads((RUNTIME/'model_manifest.json').read_text(encoding='utf-8'))
    manifest.update({'tile_source_fbx':str(FBX),'tile_source_sha256':sha(FBX),'tile_face_source':str(SOURCE),'tile_meshes':2,'tile_authoring':str(EDIT/'mahjong_tile.blend'),'tile_atlas_entries':34})
    manifest['tile_source_textures']={p.name:sha(p) for p in SOURCE.glob('T_Mahjong50_FaceAtlas_*.png')}
    (RUNTIME/'model_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('REAL_MAHJONG_IMPORT_OK',str(EDIT/'mahjong_tile.blend'))

    # Separate preview scene; canonical source remains exactly the one tile above.
    def sample(label,x,y,rotate,col,row):
        parent=bpy.data.objects.new(label,None); scene.collection.objects.link(parent); parent.location=(x,y,0); parent.rotation_euler=rotate
        for base in (ob,face):
            clone=base.copy(); clone.hide_render=False; scene.collection.objects.link(clone); clone.parent=parent
            if base==face:
                mat=face_mat.copy(); mat.node_tree.nodes['AtlasUV_Mapping'].inputs['Location'].default_value=((160+col*896)/8192,(3-row)/4,0)
                clone.data=base.data.copy(); clone.data.materials[0]=mat
        return parent
    ob.hide_render=True; face.hide_render=True
    sample('FiveCharacters',-.055,-.018,(0,0,-.12),4,0)
    sample('NineBamboo',0,.009,(0,0,.03),8,1)
    sample('OneDot',.055,-.008,(0,0,.10),0,2)
    # Lying concealed tile: rotation about local Y and translation keeps its bottom on ground.
    back=sample('GreenBack',.003,.075,(math.pi,0,-.16),0,0); back.location.z=.028
    ground,p=principled('StudioSurface',rgba('273d38'),.88)
    bpy.ops.mesh.primitive_plane_add(size=2,location=(0,0,-.0003)); bpy.context.object.data.materials.append(ground)
    def light(name,location,energy,size,color):
        data=bpy.data.lights.new(name,'AREA'); data.energy=energy; data.shape='DISK'; data.size=size; data.color=color
        obj=bpy.data.objects.new(name,data); scene.collection.objects.link(obj); obj.location=location; obj.rotation_euler=(Vector((0,.02,0))-obj.location).to_track_quat('-Z','Y').to_euler()
    light('LargeSoftbox',(-.09,-.08,.20),.45,.16,(1,.92,.80))
    light('CoolFill',(.12,.09,.12),.18,.12,(.80,.90,1))
    light('EdgeSoftbox',(0,.14,.18),.35,.10,(1,1,1))
    cam_data=bpy.data.cameras.new('ProductCamera'); cam=bpy.data.objects.new('ProductCamera',cam_data); scene.collection.objects.link(cam)
    cam.location=(.14,-.20,.28); cam.rotation_euler=(Vector((0,.025,.005))-cam.location).to_track_quat('-Z','Y').to_euler(); cam.data.type='ORTHO'; cam.data.ortho_scale=.20; scene.camera=cam
    scene.render.engine='BLENDER_EEVEE'; scene.eevee.taa_render_samples=64
    scene.render.resolution_x=1600; scene.render.resolution_y=1100; scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX'
    scene.render.filepath=str(PREVIEW/'real_mahjong_tile_preview.png')
    bpy.ops.wm.save_as_mainfile(filepath=str(PREVIEW/'real_mahjong_tile_studio.blend'))
    bpy.ops.render.render(write_still=True)
    print('REAL_MAHJONG_PREVIEW_OK',scene.render.filepath)


if __name__ == '__main__':
    main()
