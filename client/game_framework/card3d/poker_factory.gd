extends RefCounted
class_name XbdPokerFactory
## 扑克产品共用同一网格、UV、牌面及材质，双副牌按牌面缓存材质。

const CARD_SCENE = preload("res://modules/game_framework/card3d/assets/models/poker_card.glb")
const TABLE_SCENE = preload("res://modules/game_framework/card3d/assets/models/poker_table.glb")
const ART := "res://modules/game_framework/card3d/assets/cards/"
var _faces: Dictionary = {}
var _back: StandardMaterial3D

func face_path(card: Dictionary) -> String:
	var rank := int(card.get("rank", 0))
	if rank == 16: return ART + "small_joker.png"
	if rank == 17: return ART + "big_joker.png"
	var value := str(rank)
	match rank:
		11: value = "J"
		12: value = "Q"
		13: value = "K"
		14: value = "A"
		15: value = "2"
	return ART + "%s_%s.png" % [str(card.get("suit", "spade")), value]

func face_material(card: Dictionary) -> StandardMaterial3D:
	var path := face_path(card)
	if _faces.has(path): return _faces[path]
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(path)
	# Printed faces need a broad soft reflection; a sharp highlight can erase ink
	# when the user's hand tilts toward the mobile camera.
	material.roughness = 0.74
	material.metallic_specular = 0.12
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_faces[path] = material
	return material

func create_card(card: Dictionary, concealed: bool = false) -> Node3D:
	var model := CARD_SCENE.instantiate() as Node3D
	var face := model.find_child("CardFace", true, false) as MeshInstance3D
	var back := model.find_child("CardBack", true, false) as MeshInstance3D
	if face != null:
		face.visible = not concealed
		if not concealed: face.material_override = face_material(card)
	if back != null:
		if _back == null:
			_back = StandardMaterial3D.new()
			_back.albedo_texture = load(ART + "back.png")
			_back.roughness = 0.31
			_back.cull_mode = BaseMaterial3D.CULL_DISABLED
		back.material_override = _back
	if concealed: model.rotation.x = PI
	return model
