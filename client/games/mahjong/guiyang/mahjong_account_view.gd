extends VBoxContainer
## Displays the account snapshot and emits explicit account action intents.

signal action_requested(action: String, payload: Dictionary)

const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const MUTED := Color("#6a5141")
const DANGER := Color("#8d3629")

var _back: Button
var _overview: VBoxContainer
var _confirmation: VBoxContainer
var _confirmation_layout: BoxContainer
var _confirmation_copy: VBoxContainer
var _confirmation_title: Label
var _confirmation_text: Label
var _retention_text: Label
var _identity: Label
var _stored_data: Label
var _logout_scope: Label
var _logout: Button
var _delete: Button
var _acknowledge: CheckButton
var _confirm: Button
var _status: Label


func _ready() -> void:
	name = "MahjongAccountView"
	add_theme_constant_override("separation", 12)
	var header_frame := PanelContainer.new()
	var header_style := RURAL.frame(RURAL.CREAM, RURAL.GOLD, 18)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: header_style.set_content_margin(side, 10)
	header_frame.add_theme_stylebox_override("panel", header_style)
	add_child(header_frame)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	header_frame.add_child(header)
	_back = _button(header, "MahjongAccountBackButton", "返回", "account_back")
	_back.custom_minimum_size.x = 104
	var title := _label(header, "账号与隐私", 32, RURAL.INK)
	title.add_theme_font_override("font", RURAL.title_font())

	_overview = _panel(self, RURAL.PAPER, RURAL.GOLD)
	_identity = _label(_overview, "", 23, RURAL.INK)
	_stored_data = _label(_overview, "", 20, MUTED)
	var buttons := _panel(_overview, RURAL.CREAM, Color("#dec5a8"))
	_logout_scope = _label(buttons, "", 20, MUTED)
	_logout = _button(buttons, "MahjongAccountLogoutButton", "退出登录", "account_logout")
	_delete = _button(_overview, "MahjongAccountDeleteButton", "申请删除账号", "account_delete_review")
	_delete.add_theme_color_override("font_color", DANGER)

	_confirmation = _panel(self, RURAL.PAPER, Color("#b3836d"))
	_confirmation_layout = BoxContainer.new()
	_confirmation_layout.add_theme_constant_override("separation", 13)
	_confirmation.add_child(_confirmation_layout)
	_confirmation_copy = VBoxContainer.new()
	_confirmation_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirmation_copy.size_flags_stretch_ratio = 1.6
	_confirmation_layout.add_child(_confirmation_copy)
	_confirmation_title = _label(_confirmation_copy, "确认停用账号", 27, DANGER)
	_confirmation_text = _label(_confirmation_copy, "申请获受理后，此账号立即停用，所有会话都会结束。你将无法再用此账号登录或查看个人战绩。", 21, RURAL.INK)
	_retention_text = _label(_confirmation_copy, "已关联的对局、举报等记录可能因安全审核及留存要求继续保存。申请受理后进入数据留存审核。", 20, MUTED)
	var consent := VBoxContainer.new()
	consent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	consent.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	consent.add_theme_constant_override("separation", 13)
	_confirmation_layout.add_child(consent)
	_acknowledge = CheckButton.new()
	_acknowledge.name = "MahjongAccountAcknowledgeDeletion"
	_acknowledge.text = "我已了解停用及记录留存的影响"
	_acknowledge.custom_minimum_size.y = 60
	RURAL.skin_button(_acknowledge)
	_acknowledge.add_theme_font_size_override("font_size", 20)
	_acknowledge.toggled.connect(func(value: bool) -> void: action_requested.emit("account_acknowledge", {"value": value}))
	consent.add_child(_acknowledge)
	_confirm = _button(consent, "MahjongAccountConfirmDeleteButton", "确认提交删除申请", "account_delete_submit", true)
	_status = _label(self, "", 20, DANGER)
	_status.name = "MahjongAccountStatus"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	(_confirmation.get_parent() as Control).hide()
	resized.connect(_fit_confirmation)
	get_viewport().size_changed.connect(_fit_confirmation)
	_fit_confirmation()
	apply({})


func _fit_confirmation() -> void:
	var compact := size.x >= 650.0 and get_viewport_rect().size.y <= 480.0
	_confirmation_layout.vertical = not compact
	_confirmation_copy.add_theme_constant_override("separation", 10 if compact else 13)
	_confirmation_title.add_theme_font_size_override("font_size", 24 if compact else 27)
	_confirmation_text.add_theme_font_size_override("font_size", 18 if compact else 21)
	_retention_text.add_theme_font_size_override("font_size", 18 if compact else 20)


func apply(data: Dictionary) -> bool:
	if not is_node_ready(): return false
	var review := bool(data.get("confirm", false))
	var confirmation_panel := _confirmation.get_parent() as Control
	var review_changed := confirmation_panel.visible != review
	var acknowledged := bool(data.get("acknowledged", false))
	var pending := str(data.get("pending", ""))
	var can_submit := bool(data.get("can_submit", false))
	_back.text = "取消" if review else "返回"
	_back.disabled = not pending.is_empty()
	var is_guest := str(data.get("account_kind", "guest")) == "guest"
	_identity.text = "%s  ·  %s" % ["游客账号" if is_guest else "小板凳账号", str(data.get("display_name", "玩家"))]
	_stored_data.text = "为提供登录、联机和战绩，服务端保存账号标识、会话、对局和举报记录。"
	_stored_data.text += "本机会保存游客登录凭据。" if is_guest else "启用记住账号后，本机只记住用户名。"
	_logout_scope.text = "退出会结束当前会话。游客账号暂无法找回。" if is_guest else "退出会结束当前会话。再次登录需要输入账号和密码。"
	(_overview.get_parent() as Control).visible = not review
	confirmation_panel.visible = review
	_logout.disabled = not can_submit or not pending.is_empty()
	_delete.disabled = _logout.disabled
	_acknowledge.disabled = not can_submit or not pending.is_empty()
	_acknowledge.set_pressed_no_signal(acknowledged)
	_confirm.disabled = not can_submit or not acknowledged or not pending.is_empty()
	_logout.text = "正在退出……" if pending == "logout" else "退出登录"
	_confirm.text = "正在提交……" if pending == "delete" else "确认提交删除申请"
	_status.text = str(data.get("error", ""))
	_status.visible = not _status.text.is_empty()
	if review_changed and not _back.disabled:
		_back.grab_focus.call_deferred()
	return review_changed


func _panel(parent: Control, fill: Color, edge: Color) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := RURAL.frame(fill, edge, 19)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: style.set_content_margin(side, 19)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 13)
	panel.add_child(column)
	return column


func _label(parent: Control, caption: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(parent: Control, node_name: String, caption: String, action: String, primary := false) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = caption
	button.custom_minimum_size.y = 62
	RURAL.skin_button(button, primary)
	button.pressed.connect(func() -> void: action_requested.emit(action, {}))
	parent.add_child(button)
	return button
