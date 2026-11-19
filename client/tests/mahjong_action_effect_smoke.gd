extends SceneTree

const AUDIO := preload("res://modules/games/mahjong/guiyang/mahjong_audio.gd")

class TableFixture:
	extends "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
	var cues: Array[String] = []
	func _connect_socket() -> void: pass
	func _transport_open() -> bool: return true
	func _play_sound(cue: String = "discard") -> void: cues.append(cue)

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition: return
	_failed = true
	push_error(message)


func _speaks(voice: AudioStreamPlayer, clip: String) -> bool:
	return voice.playing and voice.stream != null and voice.stream.resource_path == AUDIO.VOICE_ROOT + "young/" + clip + ".wav"


func _run() -> void:
	var game := TableFixture.new()
	game.preference_file = "user://mahjong-action-effect-smoke-%d.cfg" % OS.get_process_id()
	game.match_context = {"room_id": "3924", "rule_set_id": "guiyang", "rule_version": "2.0.0", "display_name": "花开富贵"}
	root.add_child(game)
	game._handle_packet(JSON.stringify({"type": "mahjong_joined", "room_id": "3924", "match_id": "demo", "your_seat": 0}))
	var hand: Array = []
	for index in range(13):
		hand.append({"id": 20 + index, "suit": ["wan", "tong", "tiao"][index % 3], "rank": index % 9 + 1})
	var snapshot := {
		"type": "mahjong_state", "room_id": "3924", "match_id": "demo", "status": "playing", "phase": "turn",
		"rule_set_id": "guiyang", "rule_version": "2.0.0", "your_seat": 0, "turn": 1, "epoch": 6,
		"players": ["花开富贵", "青瓦", "清风徐来", "小雨"], "connected_seats": [true, true, true, true],
		"hand": hand, "hand_counts": [13, 13, 13, 13], "remaining": 50,
		"action_events": [{"sequence": 1, "seat": 3, "type": "peng"}], "discards": [],
	}
	game._handle_packet(JSON.stringify(snapshot))
	var fixed_camera: Transform3D = game._camera.get_camera_transform()
	var fixed_projection: Projection = game._camera.get_camera_projection()
	var voice: AudioStreamPlayer = game.product_audio._callout
	var impact: AudioStreamPlayer = game.product_audio._impact
	_expect(game._action_effects.get_child_count() == 0 and game.cues.is_empty() and not voice.playing and not impact.playing, "initial action history is quiet")
	snapshot.epoch = 8
	snapshot.action_events.append({"sequence": 2, "seat": 0, "type": "ming_gang"})
	game._handle_packet(JSON.stringify(snapshot))
	_expect(_speaks(voice, "gang"), "confirmed kong speaks its exact name")
	_expect(impact.playing and impact.stream == game.product_audio._impact_streams["gang"], "confirmed kong uses its own impact")
	var gang_length: float = impact.stream.get_length()
	game.product_audio.stop_action_impact()
	game.product_audio.stop_callout()
	game._handle_packet(JSON.stringify(snapshot))
	_expect(game.cues == ["gang"] and not voice.playing and not impact.playing, "duplicate kong does not repeat any channel")
	_verify_center(game, "MahjongAction2", "杠")
	await _capture("confirmed_kong.png")
	_expect(not is_instance_valid(game._camera_impact) and game._camera.get_camera_transform().is_equal_approx(fixed_camera)
		and game._camera.get_camera_projection() == fixed_projection, "Kong visual effects must leave the camera fixed")
	snapshot.epoch = 9
	snapshot.discards.append({"seat": 1, "tile": {"id": 14, "suit": "tong", "rank": 9}})
	game._handle_packet(JSON.stringify(snapshot))
	_expect(_speaks(voice, "tong_9"), "confirmed discard speaks nine dots")
	game.product_audio.stop_callout()
	game._handle_packet(JSON.stringify(snapshot))
	_expect(not voice.playing and game.cues == ["gang", "discard"], "duplicate discard does not speak again")
	game._board_lost("测试断线")
	game._handle_packet(JSON.stringify({"type": "mahjong_joined", "room_id": "3924", "match_id": "demo", "your_seat": 0}))
	snapshot.epoch = 10
	snapshot.action_events.append({"sequence": 3, "seat": 2, "type": "peng"})
	snapshot.discards.append({"seat": 2, "tile": {"id": 15, "suit": "tiao", "rank": 3}})
	game._handle_packet(JSON.stringify(snapshot))
	_expect(game._action_effects.get_child_count() == 0 and game.cues.size() == 2 and not voice.playing and not impact.playing, "reconnection uses last action and discards as a silent baseline")
	snapshot.epoch = 11
	snapshot.action_events.append({"sequence": 4, "seat": 1, "type": "peng"})
	game._handle_packet(JSON.stringify(snapshot))
	_verify_center(game, "MahjongAction4", "碰")
	_expect(_speaks(voice, "peng"), "confirmed pong speaks its exact name")
	_expect(impact.playing and impact.stream == game.product_audio._impact_streams["peng"] and impact.stream.get_length() < gang_length, "pong uses a shorter impact")
	await _capture("confirmed_pong.png")
	_expect(not is_instance_valid(game._camera_impact) and game._camera.get_camera_transform().is_equal_approx(fixed_camera)
		and game._camera.get_camera_projection() == fixed_projection, "Pong visual effects must leave the camera fixed")
	snapshot.epoch = 12
	snapshot.phase = "finished"
	snapshot.status = "finished"
	snapshot.scores = [2, -6, 2, 2]
	snapshot.winners = [0, 2]
	snapshot.action_events.append({"sequence": 5, "seat": 0, "type": "hu"})
	snapshot.action_events.append({"sequence": 6, "seat": 2, "type": "hu"})
	game._handle_packet(JSON.stringify(snapshot))
	var active := game._action_effects.get_children().filter(func(item): return not item.is_queued_for_deletion())
	_expect(active.size() == 1 and game.cues == ["gang", "discard", "peng", "settlement"], "simultaneous wins display a single effect and chime beside settlement")
	if active.size() == 1: _verify_center(game, str(active[0].name), "胡")
	_expect(_speaks(voice, "hu"), "confirmed win speaks its exact name")
	_expect(impact.playing and impact.stream == game.product_audio._impact_streams["hu"] and impact.stream.get_length() > gang_length, "win uses a longer celebratory impact")
	_expect(game._action_effects.get_index() > game._overlay_root.get_index(), "final win effect appears in front of the settlement")
	await _capture("confirmed_hu.png")
	await create_timer(1.3).timeout
	_expect(game._action_effects.get_child_count() == 0, "all animations clear after playback")
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	if not _failed: print("MAHJONG_ACTION_EFFECT_SMOKE_OK centered=true confirmed=true exact_mandarin=true distinct_impacts=true dedup=true reconnect_quiet=true input_passthrough=true")
	quit(int(_failed))


func _verify_center(game: Control, node_name: String, caption: String) -> void:
	var effect := game._action_effects.get_node_or_null(node_name) as Control
	_expect(effect != null, "confirmed action has a live animation")
	if effect == null: return
	_expect(effect.get_rect().get_center().distance_to(game.size * 0.5) <= 1.0, "action animation stays at the center of the screen")
	_expect(effect.mouse_filter == Control.MOUSE_FILTER_IGNORE and effect._caption == caption, "confirmation shows the intended character and ignores input")


func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--preview-dir="): continue
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		var path := arg.trim_prefix("--preview-dir=").path_join(filename)
		_expect(root.get_texture().get_image().save_png(path) == OK, "native screenshot was written")
