extends SceneTree

const AUDIO := preload("res://modules/games/mahjong/guiyang/mahjong_audio.gd")
const TABLE := preload("res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd")

var _errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition: _errors.append(message)


func _run() -> void:
	var pref := "user://mahjong-audio-smoke-%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
	var config := ConfigFile.new()
	config.set_value("rendering", "quality", 2)
	config.save(pref)
	var service := AUDIO.new()
	service.preference_file = pref
	root.add_child(service)
	await process_frame
	_expect(not service.music_enabled and not service._music.playing, "background music is off without a saved preference")
	service.set_music_enabled(true)
	_expect(service._music.playing and service._music.stream.loop, "an explicit music opt-in starts the loop")
	var player_id := service._music.get_instance_id()
	var screen := Control.new()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var playing_cue := service._effects
	service.play_cue("room")
	_expect(playing_cue.playing and playing_cue.stream == service._room_cue, "entry cue uses actual player")
	service.play_cue("settlement")
	_expect(playing_cue.playing and playing_cue.stream == service._settlement_cue, "settlement cue uses actual player")
	_verify_callouts(service)
	var settings_probe := service.make_callout_selector()
	root.add_child(settings_probe)
	_expect(settings_probe.item_count == 3, "three age profiles available in the picker")
	settings_probe.select(2)
	settings_probe.item_selected.emit(2)
	_expect(service.callout_voice == "senior" and service._callout.playing, "selecting another voice previews the profile")
	settings_probe.free()
	service.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	service.play_cue("discard")
	service.play_callout("hu")
	_expect(service._music.stream_paused and not playing_cue.playing and not service._callout.playing, "mobile background pauses music and drops effects and callouts")
	service.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_expect(not service._music.stream_paused, "foreground restores the loop position")
	service.open_settings(screen)
	var music := screen.find_child("MahjongMusicToggle", true, false) as Button
	var effects := screen.find_child("MahjongEffectsToggle", true, false) as Button
	service.play_callout("peng")
	music.pressed.emit()
	effects.pressed.emit()
	_expect(not service._music.playing and not playing_cue.playing and not service._callout.playing, "settings stop pending playback immediately")
	_expect(music.text.ends_with("关") and effects.text.ends_with("关"), "settings reflect preferences")
	service.play_cue("gang")
	service.play_callout("ming_gang")
	_expect(not playing_cue.playing and not service._callout.playing, "disabled effects and callouts do not queue")
	screen.free()
	config.clear()
	var loaded := config.load(pref)
	_expect(loaded == OK and config.get_value("rendering", "quality") == 2, "sound preferences preserve quality")
	_expect(config.get_value("sound", "music") == false and config.get_value("sound", "effects") == false, "sound preferences survive recreation")
	_expect(config.get_value("sound", "callout_voice") == "senior", "voice choice is persisted with sound preferences")
	service.set_music_enabled(true)
	service.set_effects_enabled(true)
	_expect(service._music.get_instance_id() == player_id and service._music.playing, "page changes and toggles keep one music player")
	var table := TABLE.new()
	table.product_audio = service
	table._build_audio()
	table._stop_audio()
	_expect(service._music.playing and service._music.get_instance_id() == player_id, "leaving a table does not stop shared music")
	_verify_cues(table)
	table.free()
	service.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pref))
	for failure in _errors: push_error(failure)
	print("MAHJONG_AUDIO_SMOKE_OK=", _errors.is_empty())
	quit(0 if _errors.is_empty() else 1)


func _verify_callouts(service: Node) -> void:
	var spoken: AudioStreamPlayer = service._callout
	var unique := {}
	for profile: String in AUDIO.VOICE_IDS:
		service.set_callout_voice(profile)
		for suit: String in AUDIO.VOICE_SUITS:
			for rank in range(1, 10):
				service.play_callout("discard", {"suit": suit, "rank": float(rank)})
				var stream := spoken.stream as AudioStreamWAV
				_expect(spoken.playing and stream != null and stream.resource_path == AUDIO.VOICE_ROOT + "%s/%s_%d.wav" % [profile,suit,rank], "discard speaks the specific %s %s tile %d" % [profile,suit,rank])
				if stream != null:
					_expect(stream.get_length() >= 0.15 and stream.get_length() <= 1.30 and not stream.stereo and stream.mix_rate == 24000, "pre-recorded speech is portable mono audio")
					unique[stream.resource_path] = true
		for action in ["peng", "ming_gang", "an_gang", "bu_gang", "hu"]:
			var name: String = "gang" if action.ends_with("gang") else action
			service.play_callout(action)
			_expect(spoken.playing and spoken.stream != null and spoken.stream.resource_path == AUDIO.VOICE_ROOT + "%s/%s.wav" % [profile,name], "confirmed %s speaks the action name in %s" % [action,profile])
			if spoken.stream != null:
				unique[spoken.stream.resource_path] = true
	_expect(unique.size() == 90, "three profiles each have 27 tiles and 3 action clips")
	service.play_cue("settlement")
	service.play_callout("hu")
	_expect(spoken.playing and service._effects.playing and service._music.playing, "callouts mix with existing sound and music")
	service.stop_callout()
	_expect(not spoken.playing and service._music.playing, "stopping table voice leaves shared music active")
	for malformed in [{"suit": "wind", "rank": 1}, {"suit": "wan", "rank": 0}, {"suit": "tong", "rank": 10}, {"suit": "tiao", "rank": 5.5}, {"suit": "wan", "rank": "5"}]:
		service.play_callout("discard", malformed)
		_expect(spoken.stream == null and not spoken.playing, "unknown or invalid tile does not speak")
	service.play_callout("hu")


func _verify_cues(table: Control) -> void:
	table._state = {"match_id": "audio-test", "status": "playing", "phase": "turn", "epoch": 10, "melds": [[], [], [], []], "discards": []}
	var duplicate: Dictionary = table._state.duplicate(true)
	var discard: Dictionary = table._state.duplicate(true)
	discard["epoch"] = 11
	discard["discards"] = [{"seat": 0, "tile": {"id": 14}}]
	_expect(table._snapshot_audio_cue(discard).is_empty(), "initial or resumed snapshots stay silent")
	table._snapshot_ready = true
	_expect(table._snapshot_audio_cue(duplicate).is_empty(), "duplicate snapshots stay silent")
	_expect(table._snapshot_audio_cue(discard) == "discard", "authoritative live discard plays once")
	var previous: Dictionary = table._state.duplicate(true)
	var meld: Dictionary = previous.duplicate(true)
	meld["epoch"] = 11
	meld["melds"][1].append({"kind": "peng"})
	_expect(table._snapshot_audio_cue(meld) == "peng", "confirmed meld plays")
	table._state = meld
	var kong: Dictionary = meld.duplicate(true)
	kong["epoch"] = 12
	kong["melds"][1][0]["kind"] = "bu_gang"
	_expect(table._snapshot_audio_cue(kong) == "gang", "completed upgrade kong plays")
	var finished: Dictionary = kong.duplicate(true)
	finished["phase"] = "finished"
	_expect(table._snapshot_audio_cue(finished) == "settlement", "live transition to settlement plays")
	finished["epoch"] = 14
	_expect(table._snapshot_audio_cue(finished).is_empty(), "missed epochs are not replayed")
