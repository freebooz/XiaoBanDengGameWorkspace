extends SceneTree
## 从登录后的大厅进入训练，再返回大厅。

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var before_design := root.content_scale_size
	var product = JSON.parse_string(FileAccess.get_file_as_string("res://product.json"))
	var game_id := str(product.get("game_id", ""))
	var script = load("res://scripts/main.gd")
	var app = script.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await process_frame
	app._request_kind = ""
	if game_id == "mahjong":
		app._http.cancel_request()
	else:
		app._http_request.cancel_request()
	app._account = {"account_id": "smoke-account", "display_name": "训练玩家"}
	app._show_lobby()
	var lobby_state = app._state
	if game_id == "mahjong":
		app._enter_training()
		if app._state != "training":
			push_error("麻将大厅无法进入训练")
			quit(1)
			return
		var game = app._screen.get_child(app._screen.get_child_count() - 1)
		if not game.training_mode or game._hand_models.size() != 14:
			push_error("麻将训练未使用三维牌")
			quit(1)
			return
		app._return_to_lobby()
		if app._state != lobby_state:
			push_error("麻将训练无法返回大厅")
			quit(1)
			return
	else:
		app._on_lobby_feature("双人训练")
		var game = app._screen_root.get_child(app._screen_root.get_child_count() - 1)
		if not game.training_mode or game._pieces_by_pos.size() != 32:
			push_error("象棋大厅无法进入三维训练")
			quit(1)
			return
		app._on_game_return_to_lobby()
		if app._state != lobby_state:
			push_error("象棋训练无法返回大厅")
			quit(1)
			return
	await process_frame
	if root.content_scale_size!=before_design:
		push_error("Returning from training did not restore the lobby display")
		quit(2)
		return
	print("TRAINING_FLOW_SMOKE_OK game=" + game_id + " lobby_display_restored=true")
	app.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit(0)
