extends Control
class_name XbdBattleChrome
## 公共横屏对局视觉：墨绿清漆、暖金细线、国风头像与清晰触控按钮。

const GOLD := Color("#deb879")
const TEXT := Color("#f7ead1")
const MUTED := Color("#9badab")
const ASSETS := "res://modules/foundation/ui/battle_assets/"
var game_title := "小板凳"
var room_id := ""
var _title: Label
var _subtitle: Label
var _room: Label

static func style(bg: Color, border: Color = GOLD, radius: int = 12) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.shadow_color = Color("#00000066")
	box.shadow_size = 8
	box.shadow_offset = Vector2(0,4)
	return box

static func skin_button(button: Button, primary: bool = false, danger: bool = false) -> void:
	var fill := Color("#cba05f") if primary else Color("#152b2a")
	if danger: fill = Color("#532a25")
	button.add_theme_stylebox_override("normal",style(fill,GOLD if primary else Color("#706447"),14))
	button.add_theme_stylebox_override("hover",style(fill.lightened(0.14),GOLD,14))
	button.add_theme_stylebox_override("pressed",style(fill.darkened(0.12),Color("#fff0c2"),14))
	button.add_theme_stylebox_override("disabled",style(Color("#172522"),Color("#344a43"),14))
	button.add_theme_color_override("font_color",Color("#221a0e") if primary else TEXT)
	button.add_theme_color_override("font_hover_color",Color("#221a0e") if primary else TEXT)
	button.add_theme_color_override("font_disabled_color",Color("#778b82"))
	button.add_theme_font_size_override("font_size",22)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

static func label(parent: Node, value: String, rect: Rect2, font_size: int = 20, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = value
	node.position = rect.position
	node.size = rect.size
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_size_override("font_size",font_size)
	node.add_theme_color_override("font_color",color)
	parent.add_child(node)
	return node

static func portrait_material(portrait_index: int) -> ShaderMaterial:
	# AtlasTexture forwards atlas UVs to canvas shaders; normalize the half atlas
	# before applying a circular mask, otherwise each portrait becomes a semicircle.
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform float portrait_origin = 0.0; void fragment(){vec4 c=texture(TEXTURE,UV);vec2 local_uv=vec2((UV.x-portrait_origin)*2.0,UV.y);float d=distance(local_uv,vec2(.5));float rim=smoothstep(.445,.46,d);c.rgb=mix(c.rgb,vec3(.87,.71,.46),rim);c.a*=1.0-smoothstep(.48,.5,d);COLOR=c;}"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("portrait_origin",0.5*float(portrait_index%2))
	return material

static func player(parent: Node, title: String, detail: String, rect: Rect2, active: bool = false, portrait_index: int = 0) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",style(Color("#14352fe8") if active else Color("#101e21ed"),GOLD if active else Color("#415852"),16))
	parent.add_child(panel)
	var avatar := TextureRect.new()
	avatar.name = "PlayerAvatar"
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var atlas := AtlasTexture.new()
	atlas.atlas = load(ASSETS+"portraits.png")
	var half := float(atlas.atlas.get_width())/2.0
	atlas.region = Rect2(half*float(portrait_index%2),0,half,float(atlas.atlas.get_height()))
	avatar.texture = atlas
	var diameter := minf(64,rect.size.y-18)
	avatar.position = Vector2(12,(rect.size.y-diameter)/2)
	avatar.size = Vector2.ONE*diameter
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.material = portrait_material(portrait_index)
	panel.add_child(avatar)
	var x := diameter+24
	var name_label := label(panel,title,Rect2(x,10,rect.size.x-x-10,30),20,TEXT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var info := label(panel,detail,Rect2(x,39,rect.size.x-x-10,rect.size.y-46),16,GOLD if active else MUTED)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return panel

static func backdrop(parent: Control, title: String, room: String) -> Control:
	var decor := XbdBattleChrome.new()
	decor.game_title = title
	decor.room_id = room
	decor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(decor)
	return decor

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base := ColorRect.new()
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){float light=exp(-4.0*length((UV-vec2(.5,.48))*vec2(1.0,1.4)));float grain=sin(UV.y*980.0+sin(UV.x*32.0)*6.0)*.003;vec3 c=mix(vec3(.025,.042,.05),vec3(.075,.145,.125),light);COLOR=vec4(c+grain,1.0);}"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	base.material = mat
	add_child(base)
	base.show_behind_parent = true
	var brand := TextureRect.new()
	brand.name = "BrandStool"
	brand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	brand.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand.texture = load(ASSETS+"stool.png")
	brand.position = Vector2(27,15)
	brand.size = Vector2(58,58)
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(brand)
	_title = label(self,game_title,Rect2(96,12,430,38),29,TEXT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_subtitle = label(self,"以棋会友 · 乐在其中" if game_title.contains("象棋") else "以牌会友 · 乐在其中",Rect2(98,49,350,24),14,MUTED)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_room = label(self,"练习桌" if room_id=="训练" else "房间 "+room_id,Rect2(590,20,240,38),21,GOLD)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if _room != null: _room.position.x = size.x*.5-120
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	var edge := Color("#9d7b4948")
	draw_style_box(style(Color.TRANSPARENT,edge,20),Rect2(10,10,w-20,h-20))
	draw_line(Vector2(28,88),Vector2(w-28,88),edge,1)
	draw_line(Vector2(28,h-95),Vector2(w-28,h-95),edge,1)
	for corner in [Vector2(20,98),Vector2(w-20,98),Vector2(20,h-107),Vector2(w-20,h-107)]:
		var sign_x := 1.0 if corner.x<w*.5 else -1.0
		var sign_y := 1.0 if corner.y<h*.5 else -1.0
		draw_polyline(PackedVector2Array([corner+Vector2(0,18*sign_y),corner,corner+Vector2(25*sign_x,0),corner+Vector2(25*sign_x,8*sign_y),corner+Vector2(8*sign_x,8*sign_y)]),Color("#bc955b88"),1.5,true)
