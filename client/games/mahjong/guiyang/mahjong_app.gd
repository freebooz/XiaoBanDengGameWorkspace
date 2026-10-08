extends Control
## 小板凳麻将独立产品壳：账号、四人匹配、准备及牌局均复用平台服务端。

const API_SCRIPT = preload("res://modules/foundation/network/api_client.gd")
const ART := "res://modules/games/mahjong/guiyang/assets/"
const GAME_SCRIPT := "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"

var _api
var _product: Dictionary = {}
var _account: Dictionary = {}
var _match: Dictionary = {}
var _screen: Control
var _http: HTTPRequest
var _timer: Timer
var _state := "boot"
var _request_kind := ""
var _local_ready := false
var _auto_flow := false
var _status: Label
var _ready_button: Button
var _seat_labels: Array[Label] = []
var _server_field: LineEdit


func _ready() -> void:
	var file := FileAccess.open("res://product.json", FileAccess.READ)
	if file != null:
		var parsed = JSON.parse_string(file.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			_product = parsed
	_api = API_SCRIPT.new()
	_auto_flow = "--auto-flow" in OS.get_cmdline_user_args()
	_screen = Control.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_screen)
	_http = HTTPRequest.new()
	_http.timeout = 7.0
	_http.request_completed.connect(_on_response)
	add_child(_http)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.8
	_timer.timeout.connect(_on_poll)
	add_child(_timer)
	_show_boot()
	_request_health()


func _texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _reset(next_state: String, background: String) -> void:
	_state = next_state
	for child in _screen.get_children():
		child.queue_free()
	_status = null
	_ready_button = null
	_server_field = null
	_seat_labels.clear()
	var image := TextureRect.new()
	image.texture = _texture(ART + "backgrounds/" + background)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(image)
	var shade := ColorRect.new()
	shade.color = Color("#031d18b8")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(shade)
	print("MAHJONG_FLOW=%s" % next_state)


func _style(color: Color, border: Color, radius: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color("#00000088")
	style.shadow_size = 7
	style.shadow_offset = Vector2(0, 4)
	return style


func _label(value: String, x: float, y: float, width: float, height: float, size: int = 24, color: Color = Color("#f9e9c5")) -> Label:
	var node := Label.new()
	node.text = value
	node.position = Vector2(x, y)
	node.size = Vector2(width, height)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	_screen.add_child(node)
	return node


func _button(value: String, x: float, y: float, width: float, height: float, action: Callable) -> Button:
	var node := Button.new()
	node.text = value
	node.position = Vector2(x, y)
	node.size = Vector2(width, height)
	node.add_theme_font_size_override("font_size", 25)
	node.add_theme_color_override("font_color", Color("#ffeac0"))
	node.add_theme_stylebox_override("normal", _style(Color("#124d40ed"), Color("#d9a441")))
	node.add_theme_stylebox_override("hover", _style(Color("#21745eea"), Color("#ffe0a0")))
	node.add_theme_stylebox_override("pressed", _style(Color("#0b352ddf"), Color("#d9a441")))
	node.pressed.connect(action)
	_screen.add_child(node)
	return node


func _header(subtitle: String) -> void:
	_label("小板凳麻将", 45, 70, 630, 80, 49)
	_label("贵阳麻将 · " + subtitle, 45, 153, 630, 48, 22, Color("#dfba76"))


func _server_input(y: float) -> void:
	_server_field = LineEdit.new()
	_server_field.placeholder_text = "服务器地址，例如 http://192.168.1.10:8080"
	_server_field.text = _api.base_url
	_server_field.position = Vector2(85, y)
	_server_field.size = Vector2(550, 62)
	_server_field.add_theme_font_size_override("font_size", 22)
	_server_field.add_theme_color_override("font_color", Color("#fff0cc"))
	_server_field.add_theme_color_override("font_placeholder_color", Color("#c3ab83"))
	_server_field.add_theme_stylebox_override("normal", _style(Color("#092c26ec"), Color("#d9a441"), 8))
	_server_field.add_theme_stylebox_override("focus", _style(Color("#0e4438f4"), Color("#ffe2a1"), 8))
	_screen.add_child(_server_field)


func _apply_server() -> bool:
	if _server_field == null or not _api.set_base_url(_server_field.text):
		if _status != null:
			_status.text = "请输入以 http:// 或 https:// 开头的服务器地址"
		return false
	return true


func _retry_server() -> void:
	if _apply_server():
		_status.text = "正在连接 %s" % _api.base_url
		_request_health()


func _show_boot() -> void:
	_reset("boot", "T_BG_Login_Guiyang.png")
	_header("正在连接")
	_status = _label("正在检查小板凳服务……", 100, 520, 520, 70, 22)
	_server_input(650)
	_button("连接服务器", 180, 760, 360, 70, _retry_server)


func _request_health() -> void:
	_request_kind = "health"
	if _http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		_http.request(_api.health_url())


func _show_login() -> void:
	_reset("login", "T_BG_Login_Guiyang.png")
	_header("以牌会友 · 乐在其中")
	_label("四人同桌 · 万筒条 108 张 · 贵阳玩法", 55, 425, 610, 90, 25)
	_button("游客登录", 145, 690, 430, 80, _login)
	_server_input(830)
	_status = _label("与平台账号和房间服务互通", 80, 920, 560, 60, 18)
	if _auto_flow:
		call_deferred("_login")


func _login() -> void:
	if _state != "login":
		return
	if not _apply_server():
		return
	_status.text = "正在登录……"
	_request_kind = "login"
	_post(_api.guest_login_url(), {})


func _show_lobby() -> void:
	_reset("lobby", "T_BG_Lobby_JiaxiuTower.png")
	_header("大厅")
	_label("欢迎，%s" % str(_account.get("display_name", "棋友")), 55, 290, 610, 70, 28)
	_label("贵阳麻将 · 四人真人对局", 65, 400, 590, 70, 27)
	_button("快速对局", 145, 565, 430, 90, _start_match)
	_button("单人训练", 145, 690, 430, 90, _enter_training)
	_label("碰 · 杠 · 胡 · 七对 · 过", 70, 815, 580, 55, 20, Color("#e6c991"))
	_status = _label("等待加入对局", 80, 1030, 560, 80, 18)
	if _auto_flow:
		call_deferred("_start_match")


func _start_match() -> void:
	if _state != "lobby":
		return
	_match = {}
	_local_ready = false
	_show_matching()
	_request_match()


func _show_matching() -> void:
	_reset("matching", "T_BG_Room_GuiyangNight.png")
	_header("正在寻找牌友")
	_status = _label("等待四位玩家进入同一房间……", 70, 520, 580, 90, 23)
	_button("取消匹配", 180, 960, 360, 70, _cancel)
	_timer.start()


func _show_room() -> void:
	_reset("room", "T_BG_Room_GuiyangNight.png")
	_header("四人房间")
	_label("房间号 %s" % str(_match.get("room_id", "")), 100, 250, 520, 80, 32)
	for seat in range(4):
		var row := PanelContainer.new()
		row.position = Vector2(65, 390 + seat * 115)
		row.size = Vector2(590, 94)
		row.add_theme_stylebox_override("panel", _style(Color("#082e27e8"), Color("#ac8248"), 14))
		_screen.add_child(row)
		var player := Label.new()
		player.position = Vector2(25, 10)
		player.size = Vector2(540, 74)
		player.add_theme_font_size_override("font_size", 22)
		player.add_theme_color_override("font_color", Color("#f9e7c1"))
		row.add_child(player)
		_seat_labels.append(player)
	_ready_button = _button("准备", 370, 960, 285, 75, _ready_up)
	_button("离开房间", 65, 960, 285, 75, _cancel)
	_status = _label("", 65, 1080, 590, 95, 19)
	_refresh_room()
	_timer.start()
	if _auto_flow:
		call_deferred("_ready_up")


func _refresh_room() -> void:
	var players: Array = _match.get("player_account_ids", [])
	for seat in range(_seat_labels.size()):
		var name := "等待加入"
		if seat < players.size():
			name = "我" if str(players[seat]) == str(_account.get("account_id", "")) else "牌友-" + str(players[seat]).right(6)
		_seat_labels[seat].text = "%s号位    %s" % [str(seat + 1), name]
	if _status != null:
		_status.text = "已准备 %d / 4 · %s" % [int(_match.get("ready_players", 0)), "等待其他牌友" if _local_ready else "点击准备后开局"]
	if _ready_button != null:
		_ready_button.disabled = _local_ready
		_ready_button.text = "已准备" if _local_ready else "准备"


func _ready_up() -> void:
	if _state != "room" or _local_ready:
		return
	_local_ready = true
	_refresh_room()
	_request_ready()


func _cancel() -> void:
	if _state != "room" and _state != "matching":
		return
	if _auto_flow:
		return
	_timer.stop()
	_request_kind = "cancel"
	_post(_api.cancel_match_url(), {"account_id": str(_account.get("account_id", ""))})


func _on_poll() -> void:
	if _state == "matching":
		_request_match()
	elif _state == "room":
		if _local_ready:
			_request_ready()
		else:
			_request_match()


func _request_match() -> void:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_timer.start()
		return
	_request_kind = "match"
	_post(_api.quick_match_url(), {
		"account_id": str(_account.get("account_id", "")),
		"product_id": str(_product.get("product_id", "xbd_mahjong")),
		"game_id": "mahjong", "rule_set_id": "guiyang",
		"rule_version": str(_product.get("rule_version", "2.0.0"))
	})


func _request_ready() -> void:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_timer.start()
		return
	_request_kind = "ready"
	_post(_api.room_ready_url(), {"account_id": str(_account.get("account_id", "")), "room_id": str(_match.get("room_id", ""))})


func _post(url: String, payload: Dictionary) -> void:
	var error := _http.request(url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK and _status != null:
		_status.text = "请求失败：%s" % str(error)


func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		if _status != null:
			_status.text = "连接失败：%s" % str(parsed.get("error", code) if typeof(parsed) == TYPE_DICTIONARY else code)
		if _state == "matching" or _state == "room":
			_timer.start()
		return
	match _request_kind:
		"health": _show_login()
		"login":
			if typeof(parsed) == TYPE_DICTIONARY and str(parsed.get("account_id", "")) != "":
				_account = parsed
				_show_lobby()
		"match":
			if typeof(parsed) != TYPE_DICTIONARY:
				return
			_match = parsed
			if bool(parsed.get("start", false)):
				_enter_game()
			elif str(parsed.get("status", "")) == "matched":
				if _state != "room":
					_show_room()
				else:
					_refresh_room()
					_timer.start()
			else:
				if _state == "room":
					_local_ready = false
					_show_matching()
				if _status != null:
					_status.text = "房间 %s · 已有 %d / 4 位牌友" % [str(parsed.get("room_id", "")), int(parsed.get("players", 1))]
				_timer.start()
		"ready":
			if typeof(parsed) != TYPE_DICTIONARY:
				return
			_match["ready_players"] = int(parsed.get("ready_players", 0))
			if bool(parsed.get("start", false)):
				_enter_game()
			else:
				_refresh_room()
				_timer.start()
		"cancel":
			_match = {}
			_local_ready = false
			_show_lobby()


func _enter_game() -> void:
	_timer.stop()
	_reset("game", "T_BG_GameTable_GreenFelt.png")
	var screen_script = load(GAME_SCRIPT)
	if screen_script == null:
		_status = _label("麻将对局模块加载失败", 60, 580, 600, 80, 22)
		return
	var game = screen_script.new()
	game.product = _product
	game.match_context = {"room_id": str(_match.get("room_id", "")), "account_id": str(_account.get("account_id", "")), "seat_index": int(_match.get("seat_index", -1))}
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if game.has_signal("request_return_to_lobby"):
		game.request_return_to_lobby.connect(_return_to_lobby)
	_screen.add_child(game)
	print("MAHJONG_ROOM=%s" % str(_match.get("room_id", "")))


func _enter_training() -> void:
	if _state != "lobby":
		return
	_reset("training", "T_BG_GameTable_GreenFelt.png")
	var screen_script = load(GAME_SCRIPT)
	if screen_script == null:
		_status = _label("麻将训练模块加载失败", 60, 580, 600, 80, 22)
		return
	var game = screen_script.new()
	game.training_mode = true
	game.match_context = {"room_id": "训练", "account_id": str(_account.get("account_id", "")), "seat_index": 0}
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.request_return_to_lobby.connect(_return_to_lobby)
	_screen.add_child(game)


func _return_to_lobby() -> void:
	_match = {}
	_local_ready = false
	_show_lobby()
