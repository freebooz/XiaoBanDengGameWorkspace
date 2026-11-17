extends RefCounted
## 原项目 Mahjong50 牌面 PBR 图集。所有实体牌共享网格与纹理，仅切换图集偏移。

const TEXTURES := "res://modules/games/mahjong/guiyang/assets/models/textures/"
const BODY_SHADER = preload("res://modules/games/mahjong/guiyang/tile_resin.gdshader")
const TABLETOP_SHADER = preload("res://modules/games/mahjong/guiyang/tile_tabletop_face.gdshader")
const IVORY_FACE := Color("#e8dfd2")
## The authored normal is concave (matched to the existing engraved height atlas).
## Share the same depth for hand, river and meld faces; no parallax/extra samples.
const ENGRAVING_NORMAL_DEPTH := 0.72
var _faces: Dictionary = {}
var _tabletop_faces: Dictionary = {}
var _body: ShaderMaterial
var _blank: StandardMaterial3D

func body() -> ShaderMaterial:
	if _body == null:
		_body = ShaderMaterial.new()
		_body.shader = BODY_SHADER
	return _body

func blank_face() -> StandardMaterial3D:
	if _blank == null:
		_blank = StandardMaterial3D.new()
		_blank.albedo_color = IVORY_FACE
		_blank.roughness = 0.36
		_blank.metallic_specular = 0.38
		_blank.clearcoat_enabled = true
		_blank.clearcoat = 0.18
		_blank.clearcoat_roughness = 0.31
	return _blank

func face(tile: Dictionary) -> StandardMaterial3D:
	var row: int
	match str(tile.get("suit", "")):
		"wan": row = 0
		"tiao": row = 1
		"tong": row = 2
		_: return blank_face()
	var rank := int(tile.get("rank", 0))
	if rank < 1 or rank > 9:
		return blank_face()
	var key := "%d:%d" % [row, rank]
	if _faces.has(key): return _faces[key]
	var material := StandardMaterial3D.new()
	material.resource_name = "Mahjong50Face_" + key
	material.albedo_color = IVORY_FACE
	material.albedo_texture = load(TEXTURES + "T_Mahjong50_FaceAtlas_BaseColor.png")
	material.normal_enabled = true
	material.normal_texture = load(TEXTURES + "T_Mahjong50_FaceAtlas_Normal.png")
	material.normal_scale = ENGRAVING_NORMAL_DEPTH
	var orm: Texture2D = load(TEXTURES + "T_Mahjong50_FaceAtlas_ORM.png")
	material.ao_enabled = true
	material.ao_texture = orm
	material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.roughness_texture = orm
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	material.roughness = 1.0
	material.metallic = 0.0
	material.metallic_specular = 0.38
	material.clearcoat_enabled = true
	material.clearcoat = 0.18
	material.clearcoat_roughness = 0.31
	# 源图集横向步距 896；图案可用宽 704、左偏移 160，禁止整图拉伸到一张牌。
	material.uv1_scale = Vector3(704.0 / 8192.0, 0.25, 1.0)
	material.uv1_offset = Vector3((160.0 + float(rank - 1) * 896.0) / 8192.0, float(row) * 0.25, 0.0)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.texture_repeat = false
	_faces[key] = material
	return material


func tabletop_face(tile: Dictionary) -> Material:
	var source := face(tile)
	if source.albedo_texture == null:
		return source
	var key := source.resource_name
	if _tabletop_faces.has(key):
		return _tabletop_faces[key]
	var material := ShaderMaterial.new()
	material.resource_name = source.resource_name + "_Tabletop"
	material.shader = TABLETOP_SHADER
	material.set_shader_parameter("face_atlas", source.albedo_texture)
	material.set_shader_parameter("face_normal", source.normal_texture)
	material.set_shader_parameter("face_orm", source.ao_texture)
	material.set_shader_parameter("atlas_origin", Vector2(source.uv1_offset.x, source.uv1_offset.y))
	material.set_shader_parameter("atlas_scale", Vector2(source.uv1_scale.x, source.uv1_scale.y))
	material.set_shader_parameter("ivory_color", source.albedo_color)
	material.set_shader_parameter("engraving_depth", source.normal_scale)
	_tabletop_faces[key] = material
	return material
