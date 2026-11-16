extends SceneTree
var _failures: Array[String] = []

func _check(condition: bool, message := "Reference assertion failed") -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

class ClubFixture:
	extends "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
	func _connect_socket() -> void: pass
	func _actions_ready() -> bool: return true
	func _build_audio() -> void:
		super._build_audio()
		# This render fixture does not exercise audio; the buttons suite does.
		_music_enabled = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var screen := ClubFixture.new()
	screen.match_context = {"room_id":"2468","seat_index":0,"display_name":"贵阳牌友"}
	root.add_child(screen)
	await process_frame
	screen.set_process(false)
	var hand: Array = []
	for index in range(14): hand.append({"id":index+1,"suit":["wan","tong","tiao"][index%3],"rank":index%9+1})
	screen._state={"room_id":"2468","status":"playing","phase":"turn","your_seat":0,"turn":0,"dealer":2,"players":["me","right","opponent","left"],"hand":hand,"hand_counts":[14,13,13,13],"scores":[0,120,-60,-60],"egg_counts":[100,0,125,null],"player_names":["贵阳牌友","稻香大叔","乡村老张","板凳阿梅"],"connected_seats":[true,true,true,true],"melds":[[],[],[],[]],"discards":[],"remaining":52,"options":[{"type":"play"}]}
	screen._render()
	await process_frame
	_check(screen._hand_models[0].rotation_degrees.x >= 75, "Reference own hand must stand upright")
	for tile in screen._pieces_root.get_children():
		if tile is Node3D and not screen._hand_models.has(tile):
			_check(absf(tile.rotation_degrees.x - 90) < 0.01, "Concealed side/opponent hands must stand upright")
	_verify_tile_bounds(screen)
	screen._deadline_tick=Time.get_ticks_msec()+12000
	screen._update_clock()
	_check(int(screen._remaining_number.text) in [11,12], "Center shows authoritative turn seconds, not wall remaining")
	_check("余牌 52" in screen._header.text and "房间2468" in screen._header.text)
	_check("888888" not in screen._header.text and "/8" not in screen._header.text and "28ms" not in screen._header.text)
	_check(screen._wind_dial._dealer == 2 and screen._wind_dial._dealer != int(screen._state.turn), "The 3D dial highlights the dealer independently of the current turn")
	var expected := ["100", "0", "125", "—"]
	for relative in range(4):
		var eggs := screen._seat_panels[relative].get_node("MahjongSeatEggs") as Label
		_check(eggs.text == expected[relative], "Battle seat shows its own egg balance and distinguishes zero from unknown")
	var mic: Button=screen._own_mic
	screen._render_seats()
	_check(is_same(mic,screen._own_mic))
	screen._select_tile(7)
	await process_frame
	var selected := screen.find_child("MahjongSelectedTileOutline",true,false) as Control
	_check(selected != null and selected.visible)
	_check(selected.mouse_filter==Control.MOUSE_FILTER_IGNORE)
	_check(not screen._play_button.disabled)
	screen._state["phase"]="reaction"
	screen._state["options"]=[{"type":"hu"},{"type":"pass"}]
	screen._render()
	_check(not screen._response_buttons["hu"].disabled and screen._response_buttons["chi"].disabled)
	_check(screen._response_buttons["hu"].get_meta("legal_emphasis",false))
	screen._state["options"]=[]
	screen._render()
	_check(screen._response_buttons["hu"].disabled and not screen._response_buttons["hu"].get_meta("legal_emphasis",false))
	# A documented synthetic public midgame is used only for the visual fixture.
	# Product code never creates fake scores, tiles or legal responses.
	var public_discards: Array=[]
	for seat in range(4):
		for index in range(5):
			public_discards.append({"seat":seat,"tile":{"id":100+seat*10+index,"suit":["wan","tong","tiao"][index%3],"rank":index%9+1},"claimed":false})
	screen._state["discards"]=public_discards
	screen._state["melds"]=[[{"kind":"peng","tiles":[{"id":300,"suit":"tong","rank":4},{"id":301,"suit":"tong","rank":4},{"id":302,"suit":"tong","rank":4}]}],[],[],[]]
	screen._state["options"]=[{"type":"hu"},{"type":"pass"}]
	screen._render()
	_check(screen._response_buttons["hu"].get_meta("legal_emphasis",false))
	await process_frame
	_verify_public_melds(screen, 3)
	# Four completed kongs leave two concealed tiles. Check all sixteen
	# public faces in the continuous seat-left lane, then restore the preview.
	var preview_state: Dictionary = screen._state.duplicate(true)
	var kongs: Array = []
	for group in range(4):
		var tiles: Array = []
		for index in range(4): tiles.append({"id":400+group*4+index,"suit":"tong","rank":group+1})
		kongs.append({"kind":"an_gang","tiles":tiles})
	screen._state["melds"]=[kongs,[],[],[]]
	screen._state["hand"]=hand.slice(0,2)
	screen._state["hand_counts"]=[2,13,13,13]
	screen._render()
	await process_frame
	_verify_public_melds(screen,16)
	screen._state=preview_state
	screen._render()
	screen._select_tile(7)
	await process_frame
	_verify_public_melds(screen,3)
	if not _failures.is_empty():
		screen.queue_free()
		await process_frame
		quit(1)
		return
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../../../artifacts/landscape/mahjong_club_reference_smoke.png")
	print("MAHJONG_CLUB_REFERENCE_OK upright_hands=true center_deadline=true true_session=true selected_outline=true stable_mic=true legal_hu_only=true public_meld_faces=16")
	screen.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _verify_tile_bounds(screen) -> void:
	var felt := screen._board_viewport.find_child("Mahjong_Felt_Surface", true, false) as MeshInstance3D
	_check(felt != null)
	var bounds: AABB = felt.global_transform * felt.get_aabb()
	for tile in screen._pieces_root.get_children():
		for mesh in tile.find_children("*", "MeshInstance3D", true, false):
			for index in range(8):
				var point: Vector3 = mesh.global_transform * mesh.get_aabb().get_endpoint(index)
				_check(point.x >= bounds.position.x and point.x <= bounds.end.x, "Standing hand leaves the felt horizontally")
				_check(point.z >= bounds.position.z and point.z <= bounds.end.z, "Standing hand leaves the felt vertically")
				_check(point.y >= bounds.end.y - 0.0005, "Standing hand penetrates the felt")

func _verify_public_melds(screen, expected_count: int) -> void:
	var found := 0
	for meld in screen._pieces_root.get_children():
		if not str(meld.name).begins_with("MahjongMeld0_"): continue
		found += 1
		var face: Rect2 = screen._projected_tile_rect(meld)
		for hand in screen._hand_models:
			_check(not face.grow(-1).intersects(_projected_body_rect(screen, hand)), "Standing own hand hides the public meld face")
		face.position += screen._board_view.position
		_check(not face.grow(-1).intersects(screen._remaining_panel.get_rect()), "Compass hides the public meld face")
		_check(not face.grow(-1).intersects(screen._actions_root.get_rect()), "Action buttons hide the public meld face")
		for card in screen._seat_panels:
			if is_instance_valid(card):
				_check(not face.grow(-1).intersects(card.get_rect()), "Player card hides the public meld face: %s %s / %s %s" % [meld.name, face, card.name, card.get_rect()])
		for discard in screen._pieces_root.get_children():
			if str(discard.name).begins_with("MahjongDiscard"):
				var public_face: Rect2 = screen._projected_tile_rect(discard)
				public_face.position += screen._board_view.position
				_check(not face.grow(-1).intersects(public_face.grow(-1)), "Discard overlaps the public meld face")
	_check(found == expected_count, "Every real public meld tile must be rendered and checked")

func _projected_body_rect(screen, model: Node3D) -> Rect2:
	var points: Array[Vector2] = []
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		for index in range(8):
			points.append(screen._camera.unproject_position(mesh.global_transform * mesh.get_aabb().get_endpoint(index)) * screen._board_view.size / Vector2(screen._board_viewport.size))
	var result := Rect2(points[0], Vector2.ZERO)
	for point in points: result = result.expand(point)
	return result
