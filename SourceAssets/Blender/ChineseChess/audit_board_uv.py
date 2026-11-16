import bpy
import numpy as np
field=bpy.data.objects['Board | red sandalwood flat plate']
coords=[]; values=[]
for face in field.data.polygons:
    if face.normal.z>.99 and face.material_index==0:
        for loop in face.loop_indices:
            p=field.matrix_world@field.data.vertices[field.data.loops[loop].vertex_index].co
            coords.append((p.x,p.y,1))
            values.append(field.data.uv_layers.active.data[loop].uv[:])
coords=np.array(coords); values=np.array(values)
transform=np.linalg.lstsq(coords,values,rcond=None)[0]
residual=(coords@transform-values)*1254
print('BOARD_UV_AFFINE_RESIDUAL_PIXELS max=',np.abs(residual).max(),'rms=',np.sqrt(np.mean(residual**2)))
assert np.abs(residual).max() < .01, 'Playing surface must use one continuous affine UV transform'
