extends Node

const MODAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_modal.gd")
## One audio service per product. Page transitions leave music playback intact.

signal preferences_changed(music: bool, effects: bool)

const THEME := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const MUSIC := preload("res://modules/games/mahjong/guiyang/assets/audio/garden_guzheng.mp3")
const TILE := preload("res://modules/games/mahjong/guiyang/assets/audio/tile_play.wav")
const PREFERENCES := "user://mahjong_visuals.cfg"
const EFFECT_PITCH := {"discard": 1.0, "peng": 0.91, "gang": 0.78}
const VOICE_ROOT := "res://modules/games/mahjong/guiyang/assets/audio/voices/"
const VOICE_IDS := ["young", "mature", "senior"]
const VOICE_NAMES := ["青年女声", "中年男声", "长辈女声"]
const VOICE_ACTIONS := ["peng", "gang", "hu"]
const VOICE_SUITS := ["wan", "tong", "tiao"]

var preference_file := PREFERENCES
var music_enabled := false
var effects_enabled := true
var callout_voice := VOICE_IDS[0]
var _music: AudioStreamPlayer
var _effects: AudioStreamPlayer
var _callout: AudioStreamPlayer
var _impact: AudioStreamPlayer
var _impact_streams: Dictionary = {}
var _voice_streams: Dictionary = {}
var _room_cue: AudioStreamWAV
var _settlement_cue: AudioStreamWAV


func _ready() -> void:
	name = "MahjongProductAudio"
	var config := ConfigFile.new()
	if config.load(preference_file) == OK:
		music_enabled = bool(config.get_value("sound", "music", music_enabled))
		effects_enabled = bool(config.get_value("sound", "effects", effects_enabled))
		var saved_voice := str(config.get_value("sound", "callout_voice", callout_voice))
		if saved_voice in VOICE_IDS:
			callout_voice = saved_voice
	_music = AudioStreamPlayer.new()
	_music.name = "MahjongBackgroundMusic"
	var loop := MUSIC.duplicate() as AudioStreamMP3
	loop.loop = true
	_music.stream = loop
	_music.volume_db = -24
	add_child(_music)
	_effects = AudioStreamPlayer.new()
	_effects.name = "MahjongEffects"
	add_child(_effects)
	_callout = AudioStreamPlayer.new()
	_callout.name = "MahjongTableCallout"
	_callout.volume_db = -8.0
	add_child(_callout)
	_impact = AudioStreamPlayer.new()
	_impact.name = "MahjongActionImpact"
	_impact.volume_db = -12.0
	add_child(_impact)
	_impact_streams = {
		# Two dry knocks, a deeper metallic strike, or a rising festive cadence.
		"peng": _impact_wave(188.0, [0.0, 0.085], [Vector2(0.085, 740.0)], 23.0, 0.29),
		"gang": _impact_wave(106.0, [0.0], [Vector2(0.0, 293.66), Vector2(0.109, 554.37)], 10.0, 0.52),
		"hu": _impact_wave(127.0, [0.0, 0.235], [Vector2(0.02, 523.25), Vector2(0.105, 659.25), Vector2(0.235, 783.99), Vector2(0.235, 1046.50)], 7.0, 0.77),
	}
	_room_cue = _chime([392.0, 523.25], 0.09, 0.19)
	_settlement_cue = _chime([392.0, 493.88, 587.33], 0.11, 0.24)
	_load_callout_voice()
	_apply_preferences()


func _exit_tree() -> void:
	for player in [_music, _effects, _callout, _impact]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null


func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_PAUSED and what != NOTIFICATION_APPLICATION_RESUMED: return
	if not is_instance_valid(_music): return
	var paused := what == NOTIFICATION_APPLICATION_PAUSED
	_music.stream_paused = paused
	if paused:
		_effects.stop()
		stop_action_impact()
		stop_callout()


func set_music_enabled(enabled: bool) -> void:
	if music_enabled == enabled: return
	music_enabled = enabled
	_store_preferences()


func set_effects_enabled(enabled: bool) -> void:
	if effects_enabled == enabled: return
	effects_enabled = enabled
	_store_preferences()


func set_callout_voice(voice: String) -> void:
	if voice == callout_voice or not voice in VOICE_IDS:
		return
	stop_callout()
	callout_voice = voice
	_load_callout_voice()
	_store_preferences()


func _load_callout_voice() -> void:
	_voice_streams.clear()
	for action: String in VOICE_ACTIONS:
		_load_callout_clip(action)
	for suit: String in VOICE_SUITS:
		for rank in range(1, 10):
			_load_callout_clip("%s_%d" % [suit, rank])


func _load_callout_clip(clip: String) -> void:
	var path := VOICE_ROOT + callout_voice + "/" + clip + ".wav"
	if ResourceLoader.exists(path, "AudioStreamWAV"):
		_voice_streams[clip] = load(path)


func make_callout_selector() -> OptionButton:
	var selector := OptionButton.new()
	selector.name = "MahjongCalloutVoice"
	selector.custom_minimum_size.y = 46
	selector.tooltip_text = "选取牌桌报牌和碰、杠、胡语音"
	for title in VOICE_NAMES:
		selector.add_item(title)
	selector.select(VOICE_IDS.find(callout_voice))
	THEME.skin_button(selector, false)
	# Popup defaults can inherit a dark interface theme while this menu is light.
	var popup := selector.get_popup()
	popup.add_theme_stylebox_override("panel", THEME.frame(THEME.PAPER, THEME.GOLD, 10, 1))
	for color in ["font_color", "font_hover_color"]:
		popup.add_theme_color_override(color, THEME.INK)
	selector.item_selected.connect(func(index: int):
		set_callout_voice(VOICE_IDS[index])
		play_callout("hu")
	)
	return selector


func _store_preferences() -> void:
	var config := ConfigFile.new()
	config.load(preference_file)
	config.set_value("sound", "music", music_enabled)
	config.set_value("sound", "effects", effects_enabled)
	config.set_value("sound", "callout_voice", callout_voice)
	var result := config.save(preference_file)
	if result != OK: push_warning("麻将音频偏好无法写入本机")
	_apply_preferences()
	preferences_changed.emit(music_enabled, effects_enabled)


func _apply_preferences() -> void:
	if music_enabled and not _music.playing:
		_music.play()
	elif not music_enabled:
		_music.stop()
	if not effects_enabled:
		_effects.stop()
		stop_action_impact()
		stop_callout()


func play_cue(cue: String) -> void:
	if not effects_enabled or not is_instance_valid(_effects): return
	if _music.stream_paused: return
	var stream: AudioStream
	var pitch := 1.0
	var volume := -17.0
	match cue:
		"room": stream = _room_cue
		"settlement": stream = _settlement_cue
		_:
			if not EFFECT_PITCH.has(cue): return
			stream = TILE
			pitch = float(EFFECT_PITCH[cue])
			volume = -14.0
	_effects.stream = stream
	_effects.pitch_scale = pitch
	_effects.volume_db = volume
	_effects.play()


func play_callout(cue: String, tile: Dictionary = {}) -> void:
	if not effects_enabled or not is_instance_valid(_callout) or _music.stream_paused: return
	var clip := ""
	if cue == "discard":
		var suit := str(tile.get("suit", ""))
		var rank: Variant = tile.get("rank", 0)
		if not suit in VOICE_SUITS or not (rank is int or rank is float): return
		if rank < 1 or rank > 9 or float(rank) != floorf(float(rank)): return
		clip = "%s_%d" % [suit, int(rank)]
	else:
		clip = "gang" if cue in ["ming_gang", "an_gang", "bu_gang"] else cue
	var stream := _voice_streams.get(clip) as AudioStreamWAV
	if stream == null: return
	_callout.stream = stream
	_callout.play()


func stop_callout() -> void:
	if is_instance_valid(_callout):
		_callout.stop()
		_callout.stream = null


func play_action_impact(action: String) -> void:
	if not effects_enabled or not is_instance_valid(_impact) or _music.stream_paused:
		return
	var kind := "gang" if action.ends_with("gang") else action
	var stream := _impact_streams.get(kind) as AudioStreamWAV
	if stream != null:
		_impact.stream = stream
		_impact.play()


func stop_action_impact() -> void:
	if is_instance_valid(_impact):
		_impact.stop()
		_impact.stream = null


func _impact_wave(fundamental: float, strikes: Array[float], bells: Array[Vector2], ring_decay: float, duration: float) -> AudioStreamWAV:
	const RATE := 22050
	var frames := ceili(duration * RATE)
	var samples := PackedByteArray()
	samples.resize(frames * 2)
	for frame in range(frames):
		var time := float(frame) / RATE
		var body := 0.0
		for strike in strikes:
			var age := time - strike
			if age < 0.0:
				continue
			var phase := TAU * (fundamental * age + 0.42 * (1.0 - exp(-age * 64.0)))
			var attack := minf(age * 350.0, 1.0)
			body += attack * (sin(phase) * exp(-age * 30.0) + 0.34 * sin(phase * 4.32) * exp(-age * 125.0))
		var metal := 0.0
		for bell in bells:
			var age := time - bell.x
			if age < 0.0:
				continue
			var phase := TAU * bell.y * age
			var attack := minf(age * 190.0, 1.0)
			metal += attack * (sin(phase) * exp(-age * ring_decay) + 0.28 * sin(phase * 2.39) * exp(-age * (ring_decay + 11.0)))
		var fade := minf((duration - time) / 0.055, 1.0)
		var sample := (0.55 * body + 0.23 * metal) * fade
		samples.encode_s16(frame * 2, roundi(clampf(sample, -0.95, 0.95) * 32767.0))
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = RATE
	wave.data = samples
	return wave


func open_settings(parent: Control) -> void:
	if parent.has_node("MahjongAudioSettings"): return
	var overlay := ColorRect.new()
	overlay.name = "MahjongAudioSettings"
	overlay.color = Color("#30251ab3")
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = minf(parent.size.x - 40, 440)
	var surface := MODAL.paper_frame(Vector4(24, 24, 24, 24))
	panel.add_theme_stylebox_override("panel", surface)
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)
	var title := Label.new()
	title.text = "声音设置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", THEME.INK)
	content.add_child(title)
	var music := _option(content, _preference_text("背景音乐", music_enabled))
	music.name = "MahjongMusicToggle"
	music.pressed.connect(func():
		set_music_enabled(not music_enabled)
		music.text = _preference_text("背景音乐", music_enabled)
	)
	var effects := _option(content, _preference_text("牌声与语音", effects_enabled))
	effects.name = "MahjongEffectsToggle"
	effects.pressed.connect(func():
		set_effects_enabled(not effects_enabled)
		effects.text = _preference_text("牌声与语音", effects_enabled)
	)
	var voices := HBoxContainer.new()
	voices.add_theme_constant_override("separation", 12)
	content.add_child(voices)
	var prompt := Label.new()
	prompt.text = "报牌嗓音"
	prompt.add_theme_color_override("font_color", THEME.INK)
	prompt.add_theme_font_size_override("font_size", 18)
	voices.add_child(prompt)
	var selector := make_callout_selector()
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voices.add_child(selector)
	var close := _option(content, "完成", true)
	close.name = "MahjongAudioSettingsClose"
	close.pressed.connect(overlay.queue_free)
	close.grab_focus()


func _option(parent: VBoxContainer, label: String, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 56
	THEME.skin_button(button, primary)
	parent.add_child(button)
	return button


func _preference_text(title: String, enabled: bool) -> String:
	return title + ("：开" if enabled else "：关")


func _chime(notes: Array[float], interval: float, decay: float) -> AudioStreamWAV:
	const RATE := 22050
	var count := ceili((decay + interval * (notes.size() - 1)) * RATE)
	var samples := PackedByteArray()
	samples.resize(count * 2)
	for frame in range(count):
		var sum := 0.0
		for index in range(notes.size()):
			var age := float(frame) / RATE - interval * index
			if age < 0.0 or age >= decay: continue
			var envelope := minf(age / 0.014, 1.0) * pow(1.0 - age / decay, 2.0)
			var phase := age * notes[index] * TAU
			sum += envelope * (sin(phase) + 0.17 * sin(phase * 2.0))
		samples.encode_s16(frame * 2, roundi(sum * 9600.0))
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = RATE
	wave.data = samples
	return wave
