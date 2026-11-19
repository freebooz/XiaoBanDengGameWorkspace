extends SceneTree
## Accepted packet -> public discard crystal and selected whole-tile materials.

class Fixture:
	extends "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
	func _connect_socket() -> void: pass
	func _actions_ready() -> bool: return true
	func _play_sound(_cue: String = "discard") -> void: pass
	func _play_callout(_cue: String, _tile: Dictionary = {}) -> void: pass
	func _report_settlement() -> void: pass

var _failed := false
var _output := ""
var _focus_script_override := ""
var _evidence: Array[Dictionary] = []

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		push_error(message)

func _packet(epoch := 2) -> Dictionary:
	var hand: Array = []
	for rank in [1,2,3,4,5,6,9]: hand.append({"id":hand.size()+1,"suit":"wan","rank":rank})
	for rank in [7,8,9]: hand.append({"id":hand.size()+1,"suit":"tong","rank":rank})
	for rank in [2,2,5,6]: hand.append({"id":hand.size()+1,"suit":"tiao","rank":rank})
	return {"type":"mahjong_state","room_id":"8614","match_id":"focus-hand","epoch":epoch,"rule_set_id":"guiyang","rule_version":"2.0.0","status":"playing","phase":"turn","your_seat":0,"turn":0,"dealer":2,"players":["a","b","c","d"],"player_names":["田埂阿牛","河湾阿梅","稻香大叔","村口小张"],"egg_counts":[100,100,100,100],"hand":hand,"hand_counts":[14,13,13,13],"melds":[[],[],[],[]],"discards":[{"seat":1,"tile":{"id":90,"suit":"wan","rank":8},"claimed":false},{"seat":2,"tile":{"id":91,"suit":"tong","rank":5},"claimed":false}],"remaining":53,"options":[{"type":"play"}],"server_now_ms":1000,"action_deadline_ms":13000}

func _capture(screen, suffix: String) -> void:
	for frame in 4: await process_frame
	if _output.is_empty() or DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_output.path_join(suffix+".png"))

func _run() -> void:
	Engine.max_fps = 0
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): _output=arg.trim_prefix("--output=")
		if arg.begins_with("--focus-script="): _focus_script_override=arg.trim_prefix("--focus-script=")
		if arg.begins_with("--coach-extension="):
			GDExtensionManager.unload_extension("res://modules/games/mahjong/guiyang/native/mahjong_coach.gdextension")
			_check(GDExtensionManager.load_extension(arg.trim_prefix("--coach-extension="))==GDExtensionManager.LOAD_STATUS_OK,"Current Rust bridge must load before constructing the native board fixture")
	var screen := Fixture.new()
	screen.match_context={"room_id":"8614","seat_index":0}
	root.add_child(screen)
	await process_frame
	# Test a single staged presentation script against an immutable runtime's
	# resources, without copying or modifying the frozen packaged project.
	if not _focus_script_override.is_empty():
		var old_focus: Node3D = screen._tile_focus
		var owner := old_focus.get_parent()
		owner.remove_child(old_focus)
		old_focus.free()
		screen._tile_focus = (load(_focus_script_override) as Script).new()
		owner.add_child(screen._tile_focus)
		screen._tile_focus.set_quality(screen._quality)
	screen._set_coach_enabled(true)
	var focus: Node3D = screen._tile_focus
	screen._handle_packet(JSON.stringify(_packet()))
	_check(not focus.marker.visible,"A packet before joining must not create a marker")
	screen._handle_packet(JSON.stringify({"type":"mahjong_joined","room_id":"8614","match_id":"focus-hand","your_seat":0}))
	screen._handle_packet(JSON.stringify(_packet()))
	for frame in 3: await process_frame
	var marker := focus.marker as MeshInstance3D
	_check(marker.visible and focus.marker_identity.ends_with(":2:2:91"),"Marker must target the last public discard")
	var target := screen._pieces_root.get_node("MahjongDiscard2_0") as Node3D
	var body := target.find_child("TileBody",true,false) as MeshInstance3D
	var bounds: AABB = body.global_transform*body.get_aabb()
	_check(is_equal_approx(marker.global_position.x,bounds.get_center().x) and is_equal_approx(marker.global_position.z,bounds.get_center().z),"Marker must remain vertically aligned to the tile")
	_check(marker.global_position.y-0.021 > bounds.end.y,"Crystal tip must float above the tile, not intersect it")
	_check(marker.rotation.is_zero_approx(),"Crystal must point vertically down")
	var vertices: PackedVector3Array = marker.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for point in vertices:
		if point.y < 0: _check(is_zero_approx(point.x) and is_zero_approx(point.z),"All lower crystal faces must converge to a vertical downward tip")
	_check((marker.material_override as StandardMaterial3D).emission_enabled and focus._marker_animation.is_running(),"Crystal requires emissive PBR and breathing animation")
	var initial_y := marker.global_position.y
	var initial_energy: float = marker.material_override.emission_energy_multiplier
	await create_timer(0.22).timeout
	_check(absf(marker.global_position.y-initial_y)>0.0001 and not is_equal_approx(marker.material_override.emission_energy_multiplier,initial_energy),"Engine animation must move the crystal and breathe its emission")
	focus._start_marker_breath()
	focus._marker_animation.pause()
	focus._marker_animation.custom_step(0.85)
	_check(absf(marker.global_position.y - focus._marker_base.y - 0.0075) < 0.00001, "The discard crystal must travel 7.5 mm on inhale")
	focus._marker_animation.play()
	var identity: String = focus.marker_identity
	var stale := _packet(1)
	stale.discards.append({"seat":3,"tile":{"id":92,"suit":"tiao","rank":6},"claimed":false})
	screen._handle_packet(JSON.stringify(stale))
	_check(focus.marker_identity==identity,"An old snapshot must not move the marker")
	var foreign := _packet(9)
	foreign.room_id="foreign-room"
	screen._handle_packet(JSON.stringify(foreign))
	foreign.room_id="8614"
	foreign.match_id="foreign-hand"
	screen._handle_packet(JSON.stringify(foreign))
	_check(focus.marker_identity==identity,"Another room/match cannot move the marker")
	var draw := _packet(3)
	draw.drawn_tile_id=14
	screen._handle_packet(JSON.stringify(draw))
	_check(focus.marker_identity==identity,"Newly drawn own hand must not steal the discard marker")
	var claimed := _packet(4)
	claimed.discards[1].claimed=true
	screen._handle_packet(JSON.stringify(claimed))
	_check(not marker.visible and focus.marker_identity.is_empty(),"Claiming the newest discard must hide the marker, not point to an older pile")
	screen._render()
	_check(not marker.visible,"Rebuilding after a claimed discard must keep the marker hidden")
	var next := _packet(5)
	next.discards[1].claimed=true
	next.discards.append({"seat":3,"tile":{"id":92,"suit":"tiao","rank":6},"claimed":false})
	next.melds[1]=[{"kind":"peng","tiles":[{"id":91,"suit":"tong","rank":5},{"id":94,"suit":"tong","rank":5},{"id":95,"suit":"tong","rank":5}]}]
	next.hand_counts[1]=10
	screen._handle_packet(JSON.stringify(next))
	_check(marker.visible and focus.marker_identity.ends_with(":3:3:92"),"The following real discard must create the next marker")
	for quality in [0,1,2]:
		screen._set_quality(quality)
		var crystal := marker.material_override as StandardMaterial3D
		_check(crystal.albedo_color.is_equal_approx(Color("#e8ffb3eb")) and crystal.emission.is_equal_approx(Color("#b5f52a")),"Last-discard crystal must use the approved yellow-green albedo and emission")
		for tint: Color in marker.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
			_check(tint.g >= tint.r and tint.r > tint.b,"Crystal facet colors must support yellow-green rather than orange")
		screen._select_tile(7)
		var selected := screen._hand_models[6] as Node3D
		var selected_body := selected.find_child("TileBody",true,false) as MeshInstance3D
		var face := selected.find_child("TileFace",true,false) as MeshInstance3D
		var original_face: StandardMaterial3D = focus._selection_materials.get(face)
		var selected_face := face.material_override as StandardMaterial3D
		_check(focus._selection_materials.size()==2,"Only the selected body and printed face need individual material copies")
		_check(selected_body.material_override.get_shader_parameter("selection_strength")>0.0,"Whole closed tile body must emit yellow-green light")
		_check(selected_body.get_child_count()==0 and not screen._selected_outline.visible,"Selection must not create a shell or 2D rectangular border")
		_check(selected_face!=original_face and selected_face.albedo_texture==original_face.albedo_texture and selected_face.uv1_offset==original_face.uv1_offset and selected_face.normal_texture==original_face.normal_texture,"Selection must retain the printed PBR atlas, UV and normal details")
		_check(selected_face.albedo_color == Color("#c3ed72") and selected_face.emission_enabled
			and selected_face.emission == Color("#a9ee2b") and selected_face.emission_texture == selected_face.albedo_texture,
			"The stronger highlight must retain the original printed characters")
		_check(screen._coach_results.size()==14,"Native Rust values must cover all fourteen legal discards")
		var badge := screen._coach_overlay.get_node("MahjongEfficiencyBadge7") as Control
		_check(badge.text=="0·8" and badge.recommended and badge.selected,"Actual 0-shanten/8-ukeire and selected/recommended states must coexist")
		for id in screen._coach_overlay._badges:
			var item: Control = screen._coach_overlay._badges[id]
			var label_rect := Rect2(item.position+item.badge_rect.position,item.badge_rect.size)
			_check(screen.get_global_rect().encloses(label_rect),"Efficiency label must remain inside the viewport")
			for model in screen._hand_models:
				var tile_rect: Rect2 = screen._projected_tile_rect(model)
				tile_rect.position+=screen._board_view.position
				_check(not label_rect.intersects(tile_rect),"Efficiency labels must keep all hand faces clear")
		_evidence.append({"quality":quality,"selection_materials":focus._selection_materials.size(),"marker_facets":marker.mesh.get_meta("facets"),"marker_id":focus.marker_identity,"selected_recommended_value":badge.text,"selection_face_emission":selected_face.emission_energy_multiplier})
		await _capture(screen,"focus-quality-%d"%quality)
	var old_face := screen._hand_models[6].find_child("TileFace",true,false) as MeshInstance3D
	var original_face_material: Material = focus._selection_materials.get(old_face)
	screen._select_tile(8)
	_check(old_face.material_override==original_face_material,"Moving selection must restore the previous tile's shared PBR material")
	_check(focus._selected_tile==screen._hand_models[7],"Selecting another hand must move the whole-tile material highlight")
	var removed := next.duplicate(true)
	removed.epoch=6
	removed.hand=removed.hand.filter(func(tile): return int(tile.id)!=8)
	removed.hand_counts[0]=13
	screen._handle_packet(JSON.stringify(removed))
	_check(screen._selected_id==0 and focus._selection_materials.is_empty(),"Accepted hand removal must clear the old selected material copies")
	var finished := removed.duplicate(true)
	finished.epoch=7
	finished.phase="finished"
	finished.status="finished"
	screen._handle_packet(JSON.stringify(finished))
	_check(not marker.visible,"Round end must clear the animated discard marker")
	screen.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(focus),"Leaving the board must release the marker, selected material copies and animation owner")
	if not _output.is_empty():
		var file:=FileAccess.open(_output.path_join("focus.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"passed":not _failed,"renderer":RenderingServer.get_current_rendering_method(),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode() if DisplayServer.get_name()!="headless" else -1,"quality":_evidence,"gates":["joined snapshot only","stale epoch rejected","other room/match rejected","drawn hand ignored","claimed latest hides without fallback","subsequent discard retargets","whole tile yellow-green emissive materials, no rectangle","three quality budgets","hand removal cleanup","finished cleanup","owner destruction cleanup"]},"\t"))
	print("MAHJONG_TILE_FOCUS_OK" if not _failed else "MAHJONG_TILE_FOCUS_FAILED")
	quit(1 if _failed else 0)
