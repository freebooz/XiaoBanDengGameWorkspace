extends SceneTree

class Fixture:
	extends "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
	var sent_actions: Array[String] = []
	func _connect_socket() -> void: pass
	func _actions_ready() -> bool: return true
	func _legal_options(kind: String) -> Array:
		# Synthetic maximum-density presentation fixture: four exposed kongs
		# cannot legally offer another kong. Keep deliberate button pressure
		# separate from the real packet/hand contract in action_legality_smoke.
		var result: Array=[]
		for option: Dictionary in _options():
			if str(option.get("type",""))==kind or (kind=="gang" and str(option.get("type","")) in ["ming_gang","an_gang","bu_gang"]): result.append(option)
		return result
	func _send(packet: Dictionary) -> void:
		_last_send_error = OK
		if str(packet.get("type","")) == "mahjong_action": sent_actions.append(str(packet.get("action","")))
	func _build_audio() -> void:
		super._build_audio()
		_music_enabled = false

var _failed := false
var _output := ""
var _evidence: Array[Dictionary] = []
var _own_seat_slots: Dictionary = {}

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		push_error(message)

func _tiles(first: int, count: int, rank: int) -> Array:
	var result: Array = []
	for i in count: result.append({"id":first+i,"suit":"tong","rank":rank})
	return result

func _state(scenario: String, viewer: int) -> Dictionary:
	var melds: Array = [[], [], [], []]
	var counts := [13,13,13,13]
	var discards: Array = []
	var per_seat := [12,12,12,12]
	if scenario == "four-seat-melds":
		counts = [7,7,7,7]
		per_seat = [18,12,12,6]
		for seat in 4:
			melds[seat] = [{"kind":"peng","tiles":_tiles(300+seat*10,3,seat+1)}, {"kind":"an_gang" if seat == (viewer+2)%4 else "ming_gang", "tiles":[{},{},{},{}] if seat == (viewer+2)%4 else _tiles(304+seat*10,4,seat+5)}]
	elif scenario.contains("four-kongs"):
		var relative := 2 if scenario.begins_with("far-") else 3 if scenario.begins_with("left-") else 1 if scenario.begins_with("right-") else 0
		var kong_seat := (viewer + relative) % 4
		counts[kong_seat] = 1
		per_seat = [8,8,8,8]
		per_seat[kong_seat] = 24
		for i in 4: melds[kong_seat].append({"kind":"ming_gang","tiles":_tiles(300+i*4,4,i+1)})
		if scenario.ends_with("overflow"):
			per_seat = [4,4,4,4]
			per_seat[kong_seat] = 36
	counts[viewer] += 1
	var hand: Array = []
	for i in counts[viewer]: hand.append({"id":i+1,"suit":["wan","tong","tiao"][i%3],"rank":i%9+1})
	for seat in 4:
		for i in per_seat[seat]: discards.append({"seat":seat,"tile":{"id":100+seat*40+i,"suit":["wan","tong","tiao"][i%3],"rank":i%9+1},"claimed":false})
	return {"room_id":"8614","match_id":"layout-only","your_seat":viewer,"status":"playing","phase":"reaction","turn":(viewer+1)%4,"dealer":2,"players":["a","b","c","d"],"player_names":["田埂阿牛","河湾阿梅","稻香大叔","村口小张"],"egg_counts":[100,100,100,100],"hand":hand,"hand_counts":counts,"discards":discards,"melds":melds,"remaining":3,"options":[{"type":"peng"},{"type":"ming_gang"},{"type":"hu"},{"type":"pass"}]}

func _body_bounds(model: Node3D) -> AABB:
	var mesh := model.find_child("TileBody", true, false) as MeshInstance3D
	return mesh.global_transform * mesh.get_aabb()

func _face(screen, model: Node3D) -> Rect2:
	var rect: Rect2 = screen._projected_tile_rect(model)
	rect.position += screen._board_view.position
	return rect

func _projected_hull(screen, model: Node3D, mesh_name := "TileFace") -> PackedVector2Array:
	var mesh := model.find_child(mesh_name,true,false) as MeshInstance3D
	var points := PackedVector2Array()
	for k in 8:
		points.append(screen._camera.unproject_position(mesh.global_transform*mesh.get_aabb().get_endpoint(k))*screen._board_view.size/Vector2(screen._board_viewport.size)+screen._board_view.position)
	var hull := Geometry2D.convex_hull(points)
	var center := Vector2.ZERO
	for point in hull: center += point
	center /= hull.size()
	for i in hull.size(): hull[i] = hull[i].move_toward(center,2.0)
	return hull


func _polygons_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for polygon in Geometry2D.intersect_polygons(a,b):
		var twice_area := 0.0
		for i in polygon.size(): twice_area += polygon[i].cross(polygon[(i+1)%polygon.size()])
		if absf(twice_area) > 2.0: return true
	return false


func _verify_own_seat_slot(screen) -> void:
	var own_seat: Rect2 = screen._seat_panels[0].get_global_rect()
	var left_seat: Rect2 = screen._seat_panels[3].get_global_rect()
	var native_size: Vector2i = screen._board_viewport.size
	if not _own_seat_slots.has(native_size):
		print("DENSE_WINDOW native=", native_size, " window=", root.size)
		_own_seat_slots[native_size] = own_seat
	_check(own_seat.is_equal_approx(_own_seat_slots[native_size]) and own_seat.is_equal_approx(screen._seat_rect(0))
		and is_equal_approx(own_seat.position.x, left_seat.position.x),
		"Local portrait must stay fixed across snapshots at %s and align with the left seat" % [native_size])


func _verify(screen, scenario: String, viewer: int) -> void:
	_verify_spot_coverage(screen, scenario)
	_verify_own_seat_slot(screen)
	var own_seat: Rect2 = screen._seat_panels[0].get_global_rect()
	for panel: Control in screen._seat_panels:
		_check(panel.size.is_equal_approx(own_seat.size), "All seat panels must use the same compact size")
	var near_play_edge: Vector2 = screen._project_to_board(Vector3(0.0, 0.0, screen.PLAY_AREA_NEAR_DEPTH))
	var far_tile_top := Vector3(0.0, screen.TILE_SIZE.z, -screen.HAND_ROW_RADIUS)
	var far_edge: Vector2 = screen._camera.unproject_position(far_tile_top) * screen._board_view.size / Vector2(screen._board_viewport.size) + screen._board_view.position
	var view: Rect2 = screen._play_area
	if viewer == 0 and scenario == "four-seat-melds" and not OS.has_feature("mobile"):
		for button in [screen._toolbar.get_child(1), screen._side_tools.get_child(0), screen._own_mic]:
			var scale: Vector2 = button.get_viewport_transform().get_scale()
			_check((button.size * scale).distance_to(Vector2(37.8, 37.8)) <= 1.0, "Round toolbar and social icons must share a 37.8 px desktop diameter")
	var far_seat: Rect2 = screen._seat_panels[2].get_rect()
	var inset := far_seat.size.y * (8.0 / 76.0)
	var band_top := maxf(view.position.y, far_seat.end.y)
	var band_center := (far_edge + near_play_edge) * 0.5
	var full_center := Vector2(view.get_center().x, (band_top + view.end.y) * 0.5)
	var social_center_y: float = (band_top + screen._side_tools.position.y) * 0.5
	var hand_center_y: float = (far_edge.y + screen._own_tile_rect(0.0, 0.0).end.y) * 0.5
	if screen._frames_player_hand():
		var bottom: float = screen._own_tile_rect(0.0, 0.0).end.y
		var gap: float = (screen.size.y - screen._safe.w - bottom) * screen.get_viewport_transform().get_scale().y
		var label_space: float = (screen.COACH_OVERLAY.LABEL_HEIGHT + screen.COACH_OVERLAY.LABEL_GAP) * screen.get_viewport_transform().get_scale().y
		_check(gap >= label_space - 0.01 and gap <= label_space + 3.0 and far_edge.y >= band_top - 0.1, "Camera must leave the label row below the hand and keep the far row below its avatar")
	else:
		_check(band_center.distance_to(full_center) <= 1.0 or (absf(hand_center_y-social_center_y) <= 1.0 and absf(band_center.x-view.get_center().x) <= 1.0), "Playable table must stay centered in the available band")
		_check(far_edge.y >= band_top and near_play_edge.y <= view.end.y, "Near playing edge and far hand must fit the safe layout band")
	var surface_transform: Transform2D = screen._board_surface.get_viewport_transform() * screen._board_surface.get_global_transform()
	_check(surface_transform.get_scale().is_equal_approx(Vector2.ONE) and is_equal_approx(screen._board_viewport.scaling_3d_scale, 1.0),
		"Board must render and present every physical pixel without image upscaling")
	var expected := 0
	var exposed: Array[Node3D] = []
	var hand_radii := {}
	var concealed_kongs := 0
	var hands: Array[Node3D] = []
	var smallest_discard := Vector2(INF,INF)
	var smallest_meld := Vector2(INF,INF)
	var own_meld_edge := -INF
	var felt := screen._board_viewport.find_child("Mahjong_Felt_Surface",true,false) as MeshInstance3D
	var felt_bounds: AABB = felt.global_transform * felt.get_aabb()
	var physical_bounds: Dictionary = {}
	for node: Node3D in screen._pieces_root.get_children():
		if not node.is_queued_for_deletion():
			physical_bounds[node] = _body_bounds(node)
			var bounds: AABB = physical_bounds[node]
			var body := node.find_child("TileBody", true, false) as MeshInstance3D
			var axes := Transform3D(node.global_basis.orthonormalized(), node.global_position)
			var dimensions: Vector3 = ((axes.affine_inverse() * body.global_transform) * body.get_aabb()).size
			_check(dimensions.is_equal_approx(Vector3(0.039, 0.028, 0.056)),
				"%s world dimensions changed in %s: %s" % [node.name, scenario, dimensions])
			_check(bounds.position.x >= felt_bounds.position.x and bounds.end.x <= felt_bounds.end.x and bounds.position.z >= felt_bounds.position.z and bounds.end.z <= felt_bounds.end.z,"Every complete tile body must remain inside the felt: %s"%node.name)
	for node in screen._pieces_root.get_children():
		if node.is_queued_for_deletion(): continue
		var tile := node as Node3D
		var is_meld := str(tile.name).begins_with("MahjongMeld")
		var is_discard := str(tile.name).begins_with("MahjongDiscard")
		if not is_meld and not is_discard:
			hands.append(tile)
			var relative := 0 if screen._hand_models.has(tile) else int(str(tile.name).trim_prefix("MahjongConcealedHand").split("_")[0])
			_check(tile.global_basis.y.is_equal_approx(Vector3.BACK.rotated(Vector3.UP, relative * PI * 0.5))
				and is_equal_approx(_body_bounds(tile).size.y, 0.056), "All four hands must stand 56 mm tall facing their owner")
			if relative != 0 or not screen._hand_models.has(tile) or screen._hand_ids[screen._hand_models.find(tile)] != screen._selected_id:
				var dial_center: Vector3 = screen._wind_dial.global_position
				var measured: float = (_body_bounds(tile).get_center() - dial_center).dot(Vector3.BACK.rotated(Vector3.UP, relative * PI * 0.5))
				hand_radii[relative] = snappedf(measured, 0.00001)
				_check(absf(measured - 0.356) < 0.0001, "Resting tile body at seat %d has the wrong radius: %.5f m" % [relative, measured])
			continue
		var bounds := _body_bounds(tile)
		for other: Node3D in physical_bounds:
			if other != tile:
				_check(not bounds.grow(-0.0002).intersects(physical_bounds[other].grow(-0.0002)),"Public body intersects another tile: %s / %s"%[tile.name,other.name])
		_check(bounds.position.x >= felt_bounds.position.x and bounds.end.x <= felt_bounds.end.x and bounds.position.z >= felt_bounds.position.z and bounds.end.z <= felt_bounds.end.z, "Public tile outside felt: %s %s" % [tile.name, bounds])
		if is_meld:
			expected += 1
			var relative := int(str(tile.name).trim_prefix("MahjongMeld").split("_")[0])
			var local: Vector3 = tile.position.rotated(Vector3.UP,-float(relative)*PI*.5)
			if relative == 0:
				own_meld_edge = maxf(own_meld_edge, local.x + screen.TILE_SIZE.x * tile.scale.x * 0.5)
			var row_offset: float = (screen.HAND_ROW_RADIUS - local.z) / (screen.TILE_SIZE.z + screen.MELD_ROW_GAP)
			_check(row_offset >= -0.001 and absf(row_offset - roundf(row_offset)) < 0.001, "Declared melds must stay in complete readable rows")
			var hand_start: float = screen._concealed_row_start(relative, screen._seat_concealed_count(relative))
			_check(local.x < hand_start,"Meld is not left of its remaining hand")
			if is_equal_approx(tile.rotation.x, PI):
				concealed_kongs += 1
				_check((tile.find_child("TileFace",true,false) as MeshInstance3D).material_override == screen._tile_materials.blank_face(),"Opponent concealed kong leaks face")
				continue
		if is_discard:
			var identity := str(tile.name).trim_prefix("MahjongDiscard").split("_")
			var relative: int = screen._relative_seat(int(identity[0]))
			var discard_index := int(identity[1])
			var count := 0
			for entry in screen._state.discards:
				if int(entry.seat) == int(identity[0]) and not entry.get("claimed", false): count += 1
			var columns := clampi(ceili(count / 2.0), 8, 12)
			var row := int(discard_index / columns)
			var local: Vector3 = tile.position.rotated(Vector3.UP,-float(relative)*PI*.5)
			var physical_length := bounds.size.z if relative%2==0 else bounds.size.x
			var physical_width := bounds.size.x if relative%2==0 else bounds.size.z
			_check(Vector3(physical_width, bounds.size.y, physical_length).is_equal_approx(Vector3(0.039, 0.028, 0.056)), "Discards must lie flat at the original size")
			var first := screen._pieces_root.get_node("MahjongDiscard%s_0" % identity[0]) as Node3D
			var first_depth := first.position.rotated(Vector3.UP, -relative * PI * 0.5).z
			_check(is_equal_approx(local.z - first_depth, row * physical_length) and local.z + physical_length * 0.5 < screen.HAND_ROW_RADIUS,
				"Discard rows must stay inside the hand and advance by one physical tile length")
		var rect := _face(screen,tile)
		if is_meld: smallest_meld = smallest_meld.min(rect.size)
		else: smallest_discard = smallest_discard.min(rect.size)
		for panel in screen._seat_panels:
			_check(not rect.grow(-1).intersects(panel.get_global_rect()), "Seat HUD hides %s: %s vs %s %s" % [tile.name, rect, panel.name, panel.get_global_rect()])
		for action in screen._response_buttons.values()+[screen._play_button]:
			if action.is_visible_in_tree(): _check(not rect.grow(-1).intersects(action.get_global_rect()),"Action hides %s"%tile.name)
		_check(not rect.grow(-1).intersects(screen._remaining_panel.get_global_rect()),"Clock hides %s"%tile.name)
		exposed.append(tile)
	if is_finite(own_meld_edge) and not screen._hand_models.is_empty():
		var first_hand: Node3D = screen._hand_models.front()
		var hand_tile_width: float = screen.TILE_SIZE.x * first_hand.scale.x
		var gap := first_hand.position.x - hand_tile_width * 0.5 - own_meld_edge
		_check(is_equal_approx(gap, hand_tile_width), "Own hand and displayed melds must have a one-tile gap")
	for i in exposed.size():
		var a := exposed[i]
		for j in range(i+1, exposed.size()):
			var b := exposed[j]
			# Adjacent perspective quads can overlap in AABB without occlusion.
			_check(not _polygons_overlap(_projected_hull(screen,a),_projected_hull(screen,b)),"Public faces overlap: %s / %s"%[a.name,b.name])
		for hand in hands:
			_check(not _polygons_overlap(_projected_hull(screen,a),_projected_hull(screen,hand,"TileBody")),"Concealed hand hides public face: %s / %s"%[a.name,hand.name])
	for hand in screen._hand_models:
		var face := _face(screen, hand)
		_check(screen._board_view.get_rect().encloses(face), "Own hand must fit the viewport")
		var body: Rect2 = screen._projected_tile_rect(hand, &"TileBody")
		for control in [screen._side_tools, screen._own_mic]:
			_check(not body.intersects(control.get_rect()), "Social control %s covers %s at %s" % [control.name, hand.name, root.size])
		for panel in screen._seat_panels:
			_check(not face.grow(-1).intersects(panel.get_global_rect()),"Seat HUD hides own hand")
	_check(expected == (28 if scenario=="four-seat-melds" else 16 if scenario.contains("four-kongs") else 0),"Meld count mismatch")
	if scenario.ends_with("overflow"):
		_check(exposed.size()==64,"All 48 discards and 16 meld tiles must remain rendered without truncation")
	if scenario=="four-seat-melds": _check(concealed_kongs==4,"Concealed kong count mismatch")
	print("DENSE_LAYOUT scenario=%s viewer=%d viewport=%s exposed=%d hidden_kongs=%d smallest_discard=%s smallest_meld=%s"%[scenario,viewer,screen.size,exposed.size(),concealed_kongs,smallest_discard,smallest_meld])
	var buttons: Dictionary = {}
	var occupied: Array[Rect2] = []
	var safe_area: Rect2 = screen._usable_modal_area()
	var hand_top: float = screen._own_hand_top()
	for kind in screen._response_buttons:
		var button: Button = screen._response_buttons[kind]
		if button.is_visible_in_tree():
			var bounds := button.get_global_rect()
			_check(bounds.size.is_equal_approx(Vector2(125.0, 56.0)), "%s action must retain the 125 × 56 discard size, got %s" % [kind, bounds.size])
			_check(safe_area.encloses(bounds) and bounds.end.y <= hand_top, "%s action must be reachable above the hand" % kind)
			for previous in occupied:
				_check(not previous.intersects(bounds), "Fixed reaction buttons must not overlap")
			occupied.append(bounds)
			buttons[kind] = [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]
	var pixel_scale: Vector2 = screen.get_viewport_transform().get_scale()
	_evidence.append({"scenario":scenario,"camera_distance":screen._camera.position.distance_to(screen.CAMERA_TARGET),"camera_vertical_fov":screen._camera.fov,"far_hand_top_logical":far_edge.y,"near_play_edge_logical":near_play_edge.y,"band_center_logical":str(band_center),"native_render_size":str(screen._board_viewport.size),"hand_radii_metres":hand_radii,"tiles_measured":physical_bounds.size()})
	_evidence.append({"scenario":scenario,"viewer":viewer,"logical_viewport":[screen.size.x,screen.size.y],"physical_window":[root.size.x,root.size.y],"public_tiles":exposed.size(),"hidden_kongs":concealed_kongs,"tile_metres":[0.039,0.028,0.056],"smallest_discard_px":[smallest_discard.x*pixel_scale.x,smallest_discard.y*pixel_scale.y],"smallest_meld_px":[smallest_meld.x*pixel_scale.x,smallest_meld.y*pixel_scale.y] if is_finite(smallest_meld.x) else [],"response_targets_logical":buttons})

func _verify_spot_coverage(screen, scenario: String) -> void:
	var spot := screen._stage.get_node("OverheadTableLight") as SpotLight3D
	var forward := -spot.global_basis.z
	for tile: Node3D in screen._pieces_root.get_children():
		if tile.is_queued_for_deletion(): continue
		var body := tile.find_child("TileBody",true,false) as MeshInstance3D
		for corner in 8:
			var delta := body.global_transform * body.get_aabb().get_endpoint(corner) - spot.global_position
			_check(delta.length() < spot.spot_range and delta.normalized().dot(forward) > cos(deg_to_rad(spot.spot_angle)),"Angled spotlight misses body corner: %s / %s"%[scenario,tile.name])

func _verify_lighting(screen) -> Dictionary:
	var records: Array[Dictionary] = []
	var compatibility := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var node_ids: Dictionary = {}
	var sky_ids: Dictionary = {}
	var panorama_id := 0
	for quality in [0,1,2,1,0,2,1]:
		var energy_scale := 0.33 if compatibility else 1.0
		screen._set_quality(quality)
		for frame in 3: await process_frame
		var active := 0
		var shadowed := 0
		for light: Light3D in screen._stage.find_children("*","Light3D",true,false):
			if node_ids.has(light.name): _check(node_ids[light.name]==light.get_instance_id(),"Quality switch replaces or duplicates a light")
			else: node_ids[light.name]=light.get_instance_id()
			if light.is_visible_in_tree() and light.light_energy>0.0:
				active+=1
				if light.shadow_enabled: shadowed+=1
		_check(active==(2 if quality==0 else 3) and shadowed==1,"Lighting must use exactly one shadow caster and one/two fills")
		var spot := screen._stage.get_node("OverheadTableLight") as SpotLight3D
		_check(spot.position.is_equal_approx(Vector3(-0.65,1.29,0.54)) and (-spot.global_basis.z).dot((-spot.global_position).normalized())>0.9999,"Main spotlight must point diagonally toward table center")
		_check(is_equal_approx(spot.light_energy,1.43*energy_scale) and spot.light_color.is_equal_approx(Color("#ffefdc")),"Main key must use the tuned warm-white light")
		_check(spot.shadow_enabled and is_zero_approx(spot.light_size) and is_equal_approx(spot.spot_angle,60.0),"Main light must use PCF with full-table coverage")
		for light_name in ["FillLight","NortheastSeatLight"]:
			var fill := screen._stage.get_node(light_name) as OmniLight3D
			var expected := 0.50 if light_name=="FillLight" else (0.40 if quality>0 else 0.0)
			var expected_white := Color("#f3f8ff") if light_name == "FillLight" else Color("#d5eaff")
			_check(not fill.shadow_enabled and is_equal_approx(fill.light_energy,expected*energy_scale),"Fill must follow quality and never cast shadows")
			_check(fill.light_color.is_equal_approx(expected_white), "Fill and rim must use their separate white points")
		var key := screen._stage.get_node("KeyLight") as DirectionalLight3D
		_check(not key.visible and not key.shadow_enabled and is_zero_approx(key.light_energy),"Old directional light must stay retired")
		var environment := (screen._stage.get_node("WorldEnvironment") as WorldEnvironment).environment
		_check(environment.ambient_light_source==Environment.AMBIENT_SOURCE_COLOR and is_equal_approx(environment.ambient_light_energy,0.14 if compatibility else 0.25),"Ambient must reveal the shadowed side of the tile")
		var tone := Environment.TONE_MAPPER_LINEAR if compatibility else Environment.TONE_MAPPER_ACES
		_check(environment.tonemap_mode == tone, "Quality changes must preserve the backend's calibrated tone mapping")
		var sky := environment.sky
		var radiance := 256 if quality==2 else 128
		_check(environment.reflected_light_source==Environment.REFLECTION_SOURCE_SKY and sky.process_mode==Sky.PROCESS_MODE_QUALITY and sky.sky_material is PanoramaSkyMaterial,"Reflection must use a static panorama sky")
		_check(sky.radiance_size==(Sky.RADIANCE_SIZE_256 if quality==2 else Sky.RADIANCE_SIZE_128),"Sky radiance budget mismatch")
		if sky_ids.has(radiance): _check(sky_ids[radiance]==sky.get_instance_id(),"Quality changes must reuse the static sky")
		else: sky_ids[radiance]=sky.get_instance_id()
		var panorama := (sky.sky_material as PanoramaSkyMaterial).panorama
		if panorama_id!=0: _check(panorama_id==panorama.get_instance_id(),"Static HDR panorama must not regenerate each quality switch")
		panorama_id=panorama.get_instance_id()
		_check(panorama.get_width()==256 and panorama.get_height()==128 and panorama.get_image().get_format()==Image.FORMAT_RGBF,"Reflection panorama must retain HDR input")
		var viewport: SubViewport=screen._board_viewport
		_check(viewport.msaa_3d==[Viewport.MSAA_2X,Viewport.MSAA_2X,Viewport.MSAA_4X][quality],"MSAA quality budget mismatch")
		_check(viewport.positional_shadow_atlas_size==[1024,2048,4096][quality] and viewport.positional_shadow_atlas_quad_0==Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_1,"Shadow atlas must reserve one map")
		_check(viewport.positional_shadow_atlas_quad_1==0 and viewport.positional_shadow_atlas_quad_2==0 and viewport.positional_shadow_atlas_quad_3==0,"Unused atlas quadrants must be disabled")
		# Independently derive physical pixels from the native window / root
		# logical viewport ratio: get_screen_transform omits canvas stretch here.
		var output: Vector2 = screen._board_view.get_global_rect().size * Vector2(root.size) / root.get_visible_rect().size
		var delta := (Vector2(viewport.size) - output).abs()
		_check(delta.x <= 1.0 and delta.y <= 1.0 and viewport.scaling_3d_scale == 1.0,
			"Every quality must render native 3D pixels across both output axes")
		_verify_spot_coverage(screen,"quality-%d"%quality)
		records.append({"quality":quality,"active_lights":active,"shadow_casters":shadowed,"main_position":[spot.position.x,spot.position.y,spot.position.z],"main_energy":spot.light_energy,"main_color":spot.light_color.to_html(),"cone_half_angle":spot.spot_angle,"shadow_atlas":viewport.positional_shadow_atlas_size,"msaa":viewport.msaa_3d,"reflection_radiance":radiance,"render_size":[viewport.size.x,viewport.size.y],"physical_output_width":output.x})
	return {"quality_transitions":records,"node_count":node_ids.size(),"all_tile_body_corners_covered":true}

func _tap(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.pressed = pressed
		event.position = point
		root.push_input(event)
		for frame in 2: await process_frame

func _verify_touch(screen) -> void:
	for i in screen._hand_models.size():
		screen._select_tile(0)
		screen.sent_actions.clear()
		var id: int = screen._hand_ids[i]
		var origin_y: float = screen._hand_models[i].position.y
		var action_dock: Rect2 = screen._actions_root.get_rect()
		await _tap(screen._board_view.get_viewport_transform()*screen._board_view.get_global_transform()*screen._projected_tile_rect(screen._hand_models[i]).get_center())
		_check(screen._selected_id == id,"Projected touch missed hand %d"%id)
		_check(screen._actions_root.get_rect().is_equal_approx(action_dock), "Raising a hand tile must keep the action dock fixed")
		_verify_own_seat_slot(screen)
		_check(screen.sent_actions.is_empty(),"First touch must only select the tile")
		for action in screen._response_buttons.values()+[screen._play_button]:
			if not action.is_visible_in_tree(): continue
			for tile in screen._pieces_root.get_children():
				if tile.is_queued_for_deletion(): continue
				var face := _face(screen,tile)
				_check(not face.grow(-1).intersects(action.get_global_rect()),"Selection lift makes action cover a tile: %s / %s"%[tile.name,action.name])
		await _tap(screen._board_view.get_viewport_transform()*screen._board_view.get_global_transform()*screen._projected_tile_rect(screen._hand_models[i]).get_center())
		_check(screen._selected_id == id and screen._hand_models[i].position.y > origin_y and screen.sent_actions.is_empty(),"Second touch during a reaction must retain selection without submitting illegal play %d"%id)
	screen._select_tile(0)
	for kind in ["peng","gang","hu","pass"]:
		screen._clear_pending_command()
		screen._refresh_connection_actions(false)
		screen.sent_actions.clear()
		for frame in 2: await process_frame
		var button := screen._response_buttons[kind] as Button
		var point := button.get_viewport_transform() * button.get_global_transform() * (button.size * 0.5)
		await _tap(point)
		if screen.sent_actions != ["ming_gang" if kind == "gang" else kind]:
			var motion := InputEventMouseMotion.new()
			motion.position = point
			Input.parse_input_event(motion)
			Input.flush_buffered_events()
			await process_frame
			_check(false, "Response target did not dispatch %s at %s (seat %s, disabled %s, hovered %s, sent %s)" %
				[kind, point, screen._state.get("your_seat"), button.disabled, root.gui_get_hovered_control(), screen.sent_actions])
	screen._clear_pending_command()
	screen._refresh_connection_actions(false)

func _verify_settlement(screen) -> void:
	screen.match_context["seat_index"] = 0
	screen.match_context["kind"] = "friend"
	screen._state = _state("fourteen-hand",0)
	screen._state.merge({"status":"finished","phase":"finished","options":[],"scores":[-70,30,20,20],"egg_deltas":[-30,13,9,8],"egg_counts":[0,113,109,108],"winners":[1],"win_from":0,"win_kind":"dian_pao","score_breakdown":{"hu":[-60,20,20,20],"gang":[-10,10,0,0],"ji":[0,0,0,0]}},true)
	screen._render()
	for frame in 4: await process_frame
	var panel: Control = screen._settlement_panel
	_check(is_instance_valid(panel),"Settlement panel was not created")
	if not is_instance_valid(panel): return
	var labels: Array[String] = []
	for label: Label in panel.find_children("*","Label",true,false): labels.append(label.text)
	_check(labels.has("-30 鸡蛋") and labels.has("+13 鸡蛋") and labels.has("+9 鸡蛋") and labels.has("+8 鸡蛋"),"Settlement must display authoritative egg transfer, not scores")
	for button: Button in panel.find_children("*","Button",true,false):
		if button.is_visible_in_tree(): _check(screen.get_global_rect().encloses(button.get_global_rect()),"Settlement button outside viewport")
	if not _output.is_empty() and DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_output.path_join("settlement.png"))
	_evidence.append({"scenario":"settlement","logical_viewport":[screen.size.x,screen.size.y],"physical_window":[root.size.x,root.size.y],"scores":[-70,30,20,20],"egg_deltas":[-30,13,9,8],"labels":labels})

func _verify_discard_dock(screen) -> void:
	screen._clear_pending_command()
	screen._coach_enabled = false
	screen._state = _state("fourteen-hand", 0)
	screen._state.phase = "turn"
	screen._state.turn = 0
	screen._state.discards.clear()
	screen._state.options = [{"type": "play"}]
	screen._render()
	await process_frame
	var heading: Label = screen._header
	_check(heading.get_theme_stylebox("normal") is StyleBoxEmpty, "The live room heading must have no background artwork")
	var reference := heading.duplicate(0) as Label
	reference.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	screen.BATTLE_ART.fit_room_heading(reference, int(heading.get_meta("room_heading_preferred_size")))
	_check(heading.get_theme_font_size("font_size") == maxi(10, reference.get_theme_font_size("font_size") - 2),
		"The live room heading must be two font sizes below the fitted base")
	reference.free()
	var discard: Button = screen._play_button
	_check(discard.is_visible_in_tree(), "A discard turn must show the discard button")
	_check(discard.size.is_equal_approx(Vector2(125.0, 56.0)), "Discard button must retain the 125 × 56 reference size")
	var gap: float = screen._own_hand_top() - discard.get_global_rect().end.y
	_check(is_equal_approx(gap, 8.0), "Discard must dock 8 design units above the raised hand envelope, got %.2f" % gap)
	var first: Rect2 = screen._projected_tile_rect(screen._hand_models.front())
	var last: Rect2 = screen._projected_tile_rect(screen._hand_models.back())
	var hand_center: float = (first.position.x + last.end.x) * 0.5 + screen._board_view.position.x
	_check(absf(discard.get_global_rect().get_center().x - hand_center) < 2.0, "Discard must line up with the center of the 3D hand")
	screen.sent_actions.clear()
	screen._select_tile(screen._hand_ids.front())
	await process_frame
	var point := discard.get_viewport_transform() * discard.get_global_transform() * (discard.size * 0.5)
	await _tap(point)
	_check(screen.sent_actions == ["play"], "Tapping the fixed discard button must submit the selected tile once")
	if not _output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_output.path_join("discard-dock.png"))


func _run() -> void:
	Engine.max_fps = 0
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): _output=arg.trim_prefix("--output=")
		if arg.begins_with("--coach-extension="):
			GDExtensionManager.unload_extension("res://modules/games/mahjong/guiyang/native/mahjong_coach.gdextension")
			_check(GDExtensionManager.load_extension(arg.trim_prefix("--coach-extension="))==GDExtensionManager.LOAD_STATUS_OK,"Current Rust bridge must load before constructing the board")
	var screen := Fixture.new()
	screen.match_context={"room_id":"8614","seat_index":0}
	root.add_child(screen)
	await process_frame
	screen.set_process(false)
	for scenario in ["four-seat-melds","four-kongs","far-four-kongs","left-four-kongs","right-four-kongs","fourteen-hand","four-kongs-overflow","far-four-kongs-overflow","left-four-kongs-overflow","right-four-kongs-overflow"]:
		for viewer in 4:
			screen.match_context["seat_index"] = viewer
			screen._state=_state(scenario,viewer)
			screen._deadline_tick = Time.get_ticks_msec()+12000
			screen._render()
			for frame in 3: await process_frame
			_verify(screen,scenario,viewer)
			if viewer==0 and not _output.is_empty() and DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(_output.path_join(scenario+".png"))
			await _verify_touch(screen)
	await _verify_discard_dock(screen)
	await _verify_settlement(screen)
	var lights: Dictionary = await _verify_lighting(screen)
	var felt := screen._board_viewport.find_child("Mahjong_Felt_Surface",true,false) as MeshInstance3D
	var felt_color: Color = felt.material_override.get_shader_parameter("felt_color")
	_check(felt_color.is_equal_approx(Color("#223b2b")),"Felt must use the green dye calibrated under the table lights")
	var pile := felt.material_override.get_shader_parameter("pile_map") as Texture2D
	_check(pile != null and pile.get_size() == Vector2(1024,1024), "The table must bind the full-resolution felt pile")
	if pile != null and DisplayServer.get_name() != "headless":
		var data := pile.get_image()
		_check(data != null and data.get_mipmap_count() == 10, "Felt mipmaps must reach 1x1 for distant fibers")
	lights["felt_color"] = felt_color.to_html()
	if not _output.is_empty():
		var file := FileAccess.open(_output.path_join("geometry.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"passed":not _failed,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode() if DisplayServer.get_name()!="headless" else -1,"lights":lights,"cases":_evidence,"input":"Viewport.push_input exercises tile picking, rejected reaction discards and legal action buttons through native GUI input."},"\t"))
	print("DENSE_LAYOUT_RESULT="+str(not _failed))
	screen.queue_free()
	await process_frame
	quit(1 if _failed else 0)
