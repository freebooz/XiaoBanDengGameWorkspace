extends RefCounted
## Construct the same physical mesh and engraved face in the game and its previews.

const SCENE := preload("res://modules/games/mahjong/guiyang/assets/models/mahjong_tile.glb")
const SIZE := Vector3(0.039, 0.028, 0.056)
const GEOMETRY_SCALE := SIZE / Vector3(0.036, 0.026, 0.050)


static func build(materials: RefCounted, tile: Dictionary, concealed := false, tabletop := false) -> Node3D:
	var model := Node3D.new()
	var geometry := SCENE.instantiate() as Node3D
	geometry.name = "TileGeometry56mm"
	# Convert the imported mesh to its physical dimensions once for every view.
	geometry.scale *= GEOMETRY_SCALE
	model.add_child(geometry)
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
