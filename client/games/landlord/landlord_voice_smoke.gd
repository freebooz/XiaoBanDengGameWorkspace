extends SceneTree
const VOICE = preload("res://modules/games/landlord/landlord_voice.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var samples := PackedVector2Array()
	for index in range(48000):
		var sample := sin(float(index)*TAU*440.0/48000.0)*0.25
		samples.append(Vector2(sample,sample))
	var payload := VOICE.encode_samples(samples,48000)
	var stream := VOICE.decode_stream(payload)
	if stream == null or stream.mix_rate!=8000 or stream.data.size()!=16000 or payload.duration_ms!=1000:
		push_error("Voice PCM resampling or validation failed")
		quit(1)
		return
	var invalid := payload.duplicate()
	invalid.duration_ms = 6000
	if VOICE.decode_stream(invalid)!=null:
		quit(2)
		return
	var voice := VOICE.new()
	voice.configure(root)
	if voice.play(payload)!=OK:
		quit(3)
		return
	voice.queue_free()
	await process_frame
	print("LANDLORD_VOICE_SMOKE_OK PCM8000=true validation=true playback=true")
	quit()
