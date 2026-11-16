extends SceneTree
## Run against the opt-in Go TestMahjongNativeVoiceRelay fixture. Never records
## a physical microphone or sends to an actual user's table.
var _transports: Array = []
var _games: Array = []
var _voices: Array = []
var _captures: Array[AudioEffectCapture] = []
var _received: Dictionary = {}
var _states: Dictionary = {}
var _failure := ""
var _directory := ""
var _room := ""
var _metrics: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _wait(check: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + roundi(seconds * 1000.0)
	while not check.call() and _failure.is_empty():
		await process_frame
		if Time.get_ticks_msec() > deadline: return false
	return _failure.is_empty()

func _run() -> void:
	_directory = OS.get_environment("XBD_NATIVE_VOICE_PROBE_DIR")
	var ready: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join("native-ready.json")))
	_room = str(ready.room_id)
	for index in 4:
		var voice = load(OS.get_environment("XBD_NATIVE_VOICE_SOURCE")).new()
		voice.configure(root)
		_voices.append(voice)
		AudioServer.add_bus()
		var bus := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, "NativeVoiceReceiver%d" % index)
		AudioServer.set_bus_mute(bus, true)
		var capture := AudioEffectCapture.new()
		capture.buffer_length = 3.0
		AudioServer.add_bus_effect(bus, capture)
		voice._playback.bus = AudioServer.get_bus_name(bus)
		_captures.append(capture)
		# Use the shipped screen's real network/voice handler without entering a
		# visible game or starting its ready/network lifecycle.
		var game = load("res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd").new()
		game._voice = voice
		game._status = Label.new()
		game._bubble_deadline = Timer.new()
		game._bubble_deadline.one_shot = true
		root.add_child(game._bubble_deadline)
		game._joined = true
		game._snapshot_ready = true
		_games.append(game)
		var transport = load("res://modules/games/mahjong/guiyang/mahjong_transport.gd").new()
		root.add_child(transport)
		_transports.append(transport)
		transport.opened.connect(func():
			transport.send({"type":"mahjong_join", "room_id":_room, "client_id":"mahjong-reference-0-%d" % index}))
		transport.packet_received.connect(func(raw: String):
			var event: Dictionary = JSON.parse_string(raw)
			match str(event.get("type", "")):
				"mahjong_state":
					game._state = event
					if event.get("status", "") == "playing": _states[index] = true
				"mahjong_social":
					game._handle_packet(raw)
					_received[index] = game._social_events.has(0)
				"mahjong_error":
					_failure = str(event.get("message", ""))
		)
		transport.start(str(ready.url), "A".repeat(43))
	if not await _wait(func(): return _states.size() == 4, 12.0):
		_finish(false, "Four native transports did not enter the isolated fixture: " + _failure)
		return
	var sender = _voices[0]
	var tone := AudioStreamWAV.new()
	tone.format = AudioStreamWAV.FORMAT_16_BITS
	tone.mix_rate = 48000
	var bytes := PackedByteArray()
	bytes.resize(48000 * 2)
	for index in 48000:
		bytes.encode_s16(index * 2, roundi(sin(float(index) * TAU * 440.0 / 48000.0) * 8192.0))
	tone.data = bytes
	sender._microphone.stream = tone
	sender._capture.clear_buffer()
	sender._recording = true
	sender._microphone.play()
	await create_timer(0.65).timeout
	var payload: Dictionary = sender.stop_recording()
	if payload.is_empty():
		_finish(false, "Synthetic microphone did not produce PCM")
		return
	payload.merge({"type":"mahjong_social", "action":"voice", "message_id":"native-tone", "match_id":_games[0]._state.match_id})
	for capture in _captures: capture.clear_buffer()
	if _transports[0].send(payload) != OK:
		_finish(false, "Native WebSocket send failed")
		return
	if not await _wait(func(): return _received.size() == 4, 5.0):
		_finish(false, "Four native screen handlers did not receive voice: " + _failure)
		return
	await create_timer(1.0).timeout
	var passed := true
	for index in 4:
		var output := _captures[index].get_buffer(_captures[index].get_frames_available())
		var energy := 0.0
		var active := 0
		for frame in output:
			energy += float(frame.x * frame.x)
			if absf(frame.x) > 0.01: active += 1
		var rms := sqrt(energy / maxi(output.size(), 1))
		_metrics.append({"peer":index, "frames":output.size(), "rms":rms, "active":active, "received":_received[index]})
		passed = passed and bool(_received[index]) and (active == 0 if index == 0 else active > 10000 and rms > 0.05)
	_finish(passed, "")

func _finish(success: bool, reason: String) -> void:
	var evidence := {"success":success, "reason":reason, "physical_microphone":false, "production_api":false, "metrics":_metrics}
	FileAccess.open(_directory.path_join("native-done.json"), FileAccess.WRITE).store_string(JSON.stringify(evidence, "\t"))
	print("MAHJONG_NATIVE_VOICE ", JSON.stringify(evidence))
	for transport in _transports:
		transport.stop()
		transport.queue_free()
	for game in _games:
		game._status.free()
		game._bubble_deadline.queue_free()
		game.free()
	for voice in _voices: voice.queue_free()
	await process_frame
	for index in 4:
		var bus := AudioServer.get_bus_index("NativeVoiceReceiver%d" % index)
		if bus >= 0: AudioServer.remove_bus(bus)
	_captures.clear()
	await create_timer(0.2).timeout
	quit(0 if success else 1)
