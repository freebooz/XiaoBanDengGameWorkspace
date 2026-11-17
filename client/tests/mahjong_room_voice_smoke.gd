extends SceneTree
## Synthetic input only: never activates the physical microphone.
const VOICE = preload("res://modules/foundation/network/room_voice.gd")
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
		push_error(description)

func _tone(rate: int, seconds: float, mode: String = "mono") -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(roundi(rate * seconds))
	for index in frames.size():
		var sample := sin(float(index) * TAU * 440.0 / rate) * 0.25
		frames[index] = Vector2(sample, -sample if mode == "opposite" else sample)
	return frames

func _peak(bytes: PackedByteArray) -> int:
	var value := 0
	for index in bytes.size() / 2:
		value = maxi(value, absi(bytes.decode_s16(index * 2)))
	return value

func _run() -> void:
	var silence := PackedVector2Array()
	silence.resize(48000)
	_check(VOICE.encode_samples(silence, 48000).is_empty(), "Silent microphone must not be announced as a voice message")
	var normal: Dictionary = VOICE.encode_samples(_tone(48000, 1.0), 48000)
	var normal_stream = VOICE.decode_stream(normal)
	_check(normal_stream != null and normal_stream.data.size() == 16000 and normal.duration_ms == 1000,
		"Valid microphone samples must remain bounded PCM8000 mono")
	var opposite: Dictionary = VOICE.encode_samples(_tone(48000, 1.0, "opposite"), 48000)
	var opposite_stream = VOICE.decode_stream(opposite)
	_check(opposite_stream != null and _peak(opposite_stream.data) > 7000,
		"Opposite-phase microphone channels must not cancel the speaker into silence")
	var invalid := normal.duplicate()
	invalid["duration_ms"] = 5001
	_check(VOICE.decode_stream(invalid) == null, "Malformed voice length must be rejected")
	var maximum: Dictionary = VOICE.encode_samples(_tone(48000, 6.0), 48000)
	_check(maximum.duration_ms == 5000, "Microphone clips must stop at five seconds")
	var voice = VOICE.new()
	voice.configure(root)
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, "VoiceSyntheticOutput")
	AudioServer.set_bus_mute(bus, true)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 3.0
	AudioServer.add_bus_effect(bus, capture)
	voice._playback.bus = "VoiceSyntheticOutput"
	_check(voice.play(normal) == OK, "Received voice must enter actual Godot playback")
	await create_timer(1.25).timeout
	var output := capture.get_buffer(capture.get_frames_available())
	var energy := 0.0
	var audible_frames := 0
	for frame in output:
		energy += float(frame.x * frame.x)
		if absf(frame.x) > 0.01: audible_frames += 1
	var rms := sqrt(energy / maxi(output.size(), 1))
	_check(rms > 0.05 and audible_frames > 10000, "Received voice must produce nonzero AudioServer output, not just a bubble")
	print("MAHJONG_VOICE_MIXER frames=", output.size(), " rms=", rms, " active=", audible_frames)
	voice.queue_free()
	await process_frame
	AudioServer.remove_bus(AudioServer.get_bus_index("VoiceSyntheticOutput"))
	capture = null
	normal_stream = null
	opposite_stream = null
	await create_timer(0.1).timeout
	if _failures.is_empty(): print("MAHJONG_ROOM_VOICE_SMOKE_OK synthetic_only=true silence_rejected=true phase_safe=true mixer=true")
	quit(0 if _failures.is_empty() else 1)
