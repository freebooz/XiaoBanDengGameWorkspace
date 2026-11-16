extends SceneTree
const DISPLAY = preload("res://modules/foundation/ui/battle_display.gd")
const CHROME = preload("res://modules/foundation/ui/battle_chrome.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var before_size := root.size
	var before_design := root.content_scale_size
	var first := Control.new()
	root.add_child(first)
	DISPLAY.enter(first)
	first.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var second := Control.new()
	root.add_child(second)
	DISPLAY.enter(second)
	if root.content_scale_size != Vector2i(1440,810):
		quit(1)
		return
	var chrome := CHROME.backdrop(first,"小板凳 · 横屏对局","1234")
	var player := CHROME.player(first,"我的搭档","27 张 · 等待出牌",Rect2(600,100,280,92),true,1)
	var button := Button.new()
	first.add_child(button)
	button.position = Vector2(1160,620)
	button.size = Vector2(230,74)
	button.text = "出牌"
	CHROME.skin_button(button,true)
	await process_frame
	var avatar: TextureRect = player.get_node("PlayerAvatar")
	var brand: TextureRect = chrome.get_node("BrandStool")
	if not Rect2(Vector2.ZERO,player.size).encloses(avatar.get_rect()) or avatar.size.x>64 or brand.size!=Vector2(58,58):
		push_error("Battle artwork exceeded its intended bounds")
		quit(4)
		return
	DISPLAY.leave(first)
	if root.content_scale_size!=Vector2i(1440,810):
		push_error("One client closed another client's landscape battle")
		quit(2)
		return
	DISPLAY.leave(second)
	if root.content_scale_size!=before_design or (DisplayServer.get_name()!="headless" and root.size!=before_size):
		push_error("Lobby display was not restored")
		quit(3)
		return
	print("BATTLE_DISPLAY_SMOKE_OK landscape=true multi_client=true lobby_restored=true artwork_bounds=true")
	quit()
