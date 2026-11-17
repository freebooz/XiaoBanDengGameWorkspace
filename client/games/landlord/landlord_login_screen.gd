extends Control
## Reference artwork with real native inputs/buttons. Authentication stays in the product app.
signal guest_login_requested
signal server_apply_requested

const ART := "res://modules/games/landlord/assets/ui/login/"
const ICON := preload("res://modules/games/landlord/login_icon.gd")
const DESIGN := Vector2(720,1280)
var server_url := ""
var phone_field: LineEdit
var password_field: LineEdit
var password_toggle: Button
var account_button: Button
var guest_button: Button
var wechat_button: Button
var register_button: Button
var forgot_button: Button
var connection_button: Button
var server_field: LineEdit
var status_label: Label
var server_dialog: ConfirmationDialog
var notice: AcceptDialog
var _portrait: TextureRect
var _items: Array[Dictionary] = []
var _textures: Dictionary = {}
var _regions: Dictionary = {}
var _eye: Control

func _ready() -> void:
	name="LandlordReferenceLogin"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var region_file:=FileAccess.open(ART+"login_atlas.json",FileAccess.READ)
	if region_file!=null:
		var parsed=JSON.parse_string(region_file.get_as_text())
		if parsed is Dictionary: _regions=parsed
	_build()
	resized.connect(_layout)
	_layout()

func _texture(file: String) -> Texture2D:
	if _textures.has(file): return _textures[file]
	var picture:=Image.new()
	if picture.load_png_from_buffer(FileAccess.get_file_as_bytes(ART+file))!=OK: return null
	var texture:=ImageTexture.create_from_image(picture)
	_textures[file]=texture
	return texture

func _atlas(kind: String) -> Texture2D:
	var region: Array=_regions.get(kind,[])
	if region.size()!=4: return null
	var atlas:=AtlasTexture.new()
	atlas.atlas=_texture("login_control_atlas.png")
	atlas.region=Rect2(region[0],region[1],region[2],region[3])
	atlas.filter_clip=true
	return atlas

func _place(node: Control, rect: Rect2, font_size: int=0) -> void:
	add_child(node)
	_items.append({"node":node,"rect":rect,"font":font_size})

func _art(texture: Texture2D) -> TextureRect:
	var art:=TextureRect.new()
	art.texture=texture
	art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode=TextureRect.STRETCH_SCALE
	return art

func _build() -> void:
	var background:=_texture("login_village_background.png")
	var wings:=_art(background)
	wings.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(wings)
	wings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade:=ColorRect.new()
	shade.color=Color("#081623b0")
	shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait=_art(background)
	add_child(_portrait)
	var input_rect:=Rect2(162,395,396,70)
	_place(_art(_atlas("input")),input_rect)
	phone_field=_field("请输入手机号",input_rect)
	phone_field.name="LandlordLoginPhone"
	phone_field.max_length=11
	phone_field.virtual_keyboard_type=LineEdit.KEYBOARD_TYPE_PHONE
	_add_icon("phone",Rect2(180,411,31,39))
	input_rect=Rect2(162,476,396,70)
	_place(_art(_atlas("input")),input_rect)
	password_field=_field("请输入密码",input_rect)
	password_field.name="LandlordLoginPassword"
	password_field.secret=true
	password_field.max_length=64
	password_field.virtual_keyboard_type=LineEdit.KEYBOARD_TYPE_PASSWORD
	_add_icon("lock",Rect2(179,491,32,40))
	password_toggle=_plain_button("",Rect2(498,488,46,46),_toggle_password)
	password_toggle.name="LandlordPasswordToggle"
	password_toggle.tooltip_text="显示密码"
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: password_toggle.add_theme_color_override(state,Color.TRANSPARENT)
	_eye=ICON.new()
	_eye.kind="eye"
	password_toggle.add_child(_eye)
	_eye.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	account_button=_wood_button("登 录",Rect2(159,564,402,72),42,_unavailable.bind("手机号登录"))
	account_button.name="LandlordAccountLogin"
	var heading_font:=preload("res://modules/foundation/ui/fonts/NotoSansCJKsc-Bold.otf")
	account_button.add_theme_font_override("font",heading_font)
	forgot_button=_plain_button("忘记密码？",Rect2(174,644,136,35),_unavailable.bind("找回密码"))
	register_button=_plain_button("注册账号",Rect2(416,644,134,35),_unavailable.bind("账号注册"))
	var divider:=Label.new()
	divider.text="│"
	divider.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	divider.add_theme_color_override("font_color",Color("#fff2d6"))
	_place(divider,Rect2(350,644,20,35),24)
	wechat_button=_wood_button("微信登录",Rect2(160,685,190,68),24,_unavailable.bind("微信登录"))
	guest_button=_wood_button("游客登录",Rect2(370,685,190,68),24,func(): guest_login_requested.emit())
	guest_button.name="LandlordGuestLogin"
	wechat_button.name="LandlordWechatLogin"
	_add_icon("wechat",Rect2(174,699,38,40))
	_add_icon("guest",Rect2(387,699,38,40))
	for button in [wechat_button,guest_button]: button.alignment=HORIZONTAL_ALIGNMENT_RIGHT
	status_label=Label.new()
	status_label.name="LandlordLoginStatus"
	status_label.text="当前开放游客登录"
	status_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color",Color("#fff1cf"))
	status_label.add_theme_color_override("font_shadow_color",Color("#102334"))
	status_label.add_theme_constant_override("shadow_offset_y",2)
	_place(status_label,Rect2(120,756,480,48),16)
	connection_button=_plain_button("连接设置",Rect2(584,1236,112,30),_open_server)
	connection_button.name="LandlordLoginConnectionSettings"
	server_dialog=ConfirmationDialog.new()
	server_dialog.title="连接设置"
	server_dialog.ok_button_text="连接"
	server_dialog.cancel_button_text="取消"
	add_child(server_dialog)
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	server_dialog.add_child(box)
	var server_caption:=Label.new()
	server_caption.text="填写小板凳服务器地址"
	box.add_child(server_caption)
	server_field=LineEdit.new()
	server_field.name="LandlordLoginServerAddress"
	server_field.text=server_url
	server_field.placeholder_text="http://192.168.1.10:8080"
	server_field.custom_minimum_size=Vector2(280,44)
	server_field.virtual_keyboard_type=LineEdit.KEYBOARD_TYPE_URL
	box.add_child(server_field)
	server_dialog.confirmed.connect(func(): server_apply_requested.emit())
	server_dialog.canceled.connect(func(): server_field.text=server_url)
	notice=AcceptDialog.new()
	notice.title="账号登录"
	notice.ok_button_text="知道了"
	notice.dialog_autowrap=true
	add_child(notice)

func _field(placeholder: String, rect: Rect2) -> LineEdit:
	var field:=LineEdit.new()
	field.placeholder_text=placeholder
	for state in ["normal","focus","read_only"]:
		var style:=StyleBoxEmpty.new()
		style.content_margin_left=64
		style.content_margin_right=62 if placeholder=="请输入密码" else 18
		field.add_theme_stylebox_override(state,style)
	field.add_theme_color_override("font_color",Color("#573924"))
	field.add_theme_color_override("font_placeholder_color",Color("#a19482"))
	field.add_theme_color_override("caret_color",Color("#8b5936"))
	field.add_theme_color_override("selection_color",Color("#b4833f66"))
	_place(field,rect,24)
	return field

func _plain_button(text: String, rect: Rect2, callback: Callable) -> Button:
	var button:=Button.new()
	button.text=text
	for state in ["normal","hover","pressed","disabled"]: button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	var focus:=StyleBoxFlat.new()
	focus.bg_color=Color.TRANSPARENT
	focus.border_color=Color("#ffe2a4")
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(8)
	button.add_theme_stylebox_override("focus",focus)
	button.add_theme_color_override("font_color",Color("#fff7e3"))
	button.add_theme_color_override("font_hover_color",Color("#ffdf8e"))
	button.pressed.connect(callback)
	_place(button,rect,21)
	return button

func _wood_button(text: String, rect: Rect2, font_size: int, callback: Callable) -> Button:
	var artwork:=_art(_atlas("button"))
	_place(artwork,rect)
	var button:=_plain_button(text,rect,callback)
	button.draw.connect(_sync_button_art.bind(button,artwork))
	button.add_theme_color_override("font_color",Color("#462307"))
	button.add_theme_color_override("font_hover_color",Color("#683913"))
	button.add_theme_color_override("font_pressed_color",Color("#271305"))
	button.add_theme_color_override("font_disabled_color",Color("#785b32"))
	for entry in _items:
		if entry.node==button: entry.font=font_size
	return button

func _sync_button_art(button: Button, artwork: TextureRect) -> void:
	match button.get_draw_mode():
		BaseButton.DRAW_DISABLED: artwork.self_modulate=Color(.82,.82,.82)
		BaseButton.DRAW_PRESSED,BaseButton.DRAW_HOVER_PRESSED: artwork.self_modulate=Color(.84,.82,.77)
		BaseButton.DRAW_HOVER: artwork.self_modulate=Color(1.08,1.06,1.02)
		_: artwork.self_modulate=Color.WHITE

func _add_icon(kind: String, rect: Rect2) -> void:
	var icon:=ICON.new()
	icon.kind=kind
	_place(icon,rect)

func _layout() -> void:
	var factor:=minf(size.x/DESIGN.x,size.y/DESIGN.y)
	var offset:=(size-DESIGN*factor)*.5
	_portrait.position=offset
	_portrait.size=DESIGN*factor
	for entry in _items:
		var node: Control=entry.node
		var rect: Rect2=entry.rect
		node.position=offset+rect.position*factor
		node.size=rect.size*factor
		if int(entry.font)>0: node.add_theme_font_size_override("font_size",maxi(12,roundi(entry.font*factor)))
		if node is LineEdit:
			for state in ["normal","focus","read_only"]:
				var style:=node.get_theme_stylebox(state).duplicate() as StyleBox
				style.content_margin_left=64*factor
				style.content_margin_right=(62 if node==password_field else 18)*factor
				node.add_theme_stylebox_override(state,style)
		if node==wechat_button or node==guest_button:
			button_margin(node,18*factor)

func button_margin(button: Button, margin: float) -> void:
	for state in ["normal","hover","pressed","disabled"]:
		var style:=StyleBoxEmpty.new()
		style.content_margin_right=margin
		button.add_theme_stylebox_override(state,style)

func _toggle_password() -> void:
	password_field.secret=not password_field.secret
	password_toggle.tooltip_text="显示密码" if password_field.secret else "隐藏密码"
	_eye.revealed=not password_field.secret
	_eye.queue_redraw()

func _unavailable(feature: String) -> void:
	notice.dialog_text="%s暂未开放。\n现在可以使用游客登录进入大厅。"%feature
	notice.popup_centered_clamped(Vector2i(360,160),.90)

func _open_server() -> void:
	server_field.text=server_url
	server_dialog.popup_centered_clamped(Vector2i(420,180),.90)

func set_busy(busy: bool) -> void:
	guest_button.disabled=busy
	connection_button.disabled=busy
	status_label.text="正在登录……" if busy else "当前开放游客登录"
