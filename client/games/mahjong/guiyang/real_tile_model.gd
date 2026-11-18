extends RefCounted
## Construct the same physical mesh and engraved face in the game and its previews.

const SCENE := preload("res://modules/games/mahjong/guiyang/assets/models/mahjong_tile.glb")
const SIZE := Vector3(0.039, 0.028, 0.056) # Authored TileBody bounds in metres (width, thickness, height).


static func build(materials: RefCounted, tile: Dictionary, concealed := false, tabletop := false) -> Node3D:
	var model := SCENE.instantiate() as Node3D
	var face := model.find_child("TileFace", true, false) as MeshInstance3D
	if face != null:
		# The solid body already casts this tile's contact shadow. The thin
		# face insert uses the same footprint and needs only the color pass.
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if concealed:
			face.material_override = materials.blank_face()
		elif tabletop:
			face.material_override = materials.tabletop_face(tile)
		else:
			face.material_override = materials.face(tile)
	var body := model.find_child("TileBody", true, false) as MeshInstance3D
	if body != null: body.material_override = materials.body()
	return model
