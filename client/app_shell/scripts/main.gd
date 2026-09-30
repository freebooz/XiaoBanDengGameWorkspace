extends Control
## Main（客户端主入口）
## 读取产品清单并构建最小可运行大厅。正式项目可在此基础上替换为完整UI资源。

var _product: Dictionary = {}
var _status_label: Label


func _ready() -> void:
	_product = _load_product_config()
	# 棋牌游戏产品统一进入三维桌面表现层；2D只保留HUD、菜单、提示和AI叠加。
	var game_id := str(_product.get("game_id", ""))
	if game_id == "chinese_chess":
		_build_game_screen("res://modules/games/chinese_chess/chinese_chess_3d_screen.gd")
		return
	if game_id == "mahjong":
		_build_game_screen("res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd")
		return
	_build_ui()


func _load_product_config() -> Dictionary:
	var file := FileAccess.open("res://product.json", FileAccess.READ)
	if file == null:
		push_error("未找到 product.json，请通过 tools/compose-godot.ps1 生成产品工程。")
		return {
			"display_name": "小板凳开发壳",
			"product_id": "unknown",
			"game_id": "unknown",
			"rule_set_id": "unknown",
			"rule_version": "0.0.0"
		}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("product.json 格式错误")
		return {}
	return parsed


func _build_game_screen(script_path: String) -> void:
	var screen_script = load(script_path)
	if screen_script == null:
		push_error("未找到三维游戏界面模块：%s" % script_path)
		_build_ui()
		return
	var screen = screen_script.new()
	screen.set("product", _product)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("#f6f0e2")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(560, 420)
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_theme_constant_override("separation", 18)
	center.add_child(panel)

	var brand := Label.new()
	brand.text = "小板凳"
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.add_theme_font_size_override("font_size", 42)
	panel.add_child(brand)

	var title := Label.new()
	title.text = str(_product.get("display_name", "未配置产品"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	panel.add_child(title)

	var identity := Label.new()
	identity.text = "ProductId: %s\nGameId: %s\nRuleSetId: %s\nRuleVersion: %s" % [
		_product.get("product_id", ""),
		_product.get("game_id", ""),
		_product.get("rule_set_id", ""),
		_product.get("rule_version", "")
	]
	identity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(identity)

	var login_button := Button.new()
	login_button.text = "游客登录（本地演示）"
	login_button.pressed.connect(_on_guest_login)
	panel.add_child(login_button)

	var demo_button := Button.new()
	demo_button.text = "进入游戏规则演示"
	demo_button.pressed.connect(_on_demo)
	panel.add_child(demo_button)

	var ai_button := Button.new()
	ai_button.text = "AI能力（一期预留）"
	ai_button.pressed.connect(_on_ai)
	panel.add_child(ai_button)

	_status_label = Label.new()
	_status_label.text = "状态：等待操作"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_status_label)


func _on_guest_login() -> void:
	# 当前演示不伪造线上Token；真实登录由 ApiClient 调用统一后端。
	_status_label.text = "状态：本地游客演示已进入。正式环境使用统一 AccountId。"


func _on_demo() -> void:
	var game_id := str(_product.get("game_id", ""))
	if game_id == "chinese_chess":
		var script = load("res://modules/games/chinese_chess/chinese_chess_controller.gd")
		var controller = script.new()
		_status_label.text = controller.demo_summary()
	elif game_id == "mahjong":
		var script = load("res://modules/games/mahjong/guiyang/guiyang_controller.gd")
		var controller = script.new()
		_status_label.text = controller.demo_summary()
	else:
		_status_label.text = "状态：当前产品没有已装载的游戏模块。"


func _on_ai() -> void:
	var script = load("res://modules/foundation/ai/ai_client_facade.gd")
	var facade = script.new()
	_status_label.text = facade.describe_phase1()