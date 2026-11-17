extends SceneTree
## Full five-second voice clips through native Godot buffers and actual server.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var deadline := Time.get_ticks_msec()+15000
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	while app._state != "login":
		await process_frame
		if Time.get_ticks_msec()>deadline: quit(1); return
	app._login()
	while app._state != "lobby":
		await process_frame
		if Time.get_ticks_msec()>deadline: quit(1); return
	app._enter_training()
	var game = app._screen.get_child(app._screen.get_child_count()-1)
	while game._state.is_empty():
		await process_frame
		if Time.get_ticks_msec()>deadline: quit(1); return
	for rate in [8000,16000]:
		var pcm := PackedByteArray()
		pcm.resize(rate*5*2)
		pcm.fill(0)
		var encoded := Marshalls.raw_to_base64(pcm)
		game._social_events.clear()
		if not game._submit_social({"type":"landlord_social","action":"voice","sample_rate":rate,"duration_ms":5000,"pcm_base64":encoded}):
			push_error("Native socket did not submit maximum voice clip")
			quit(2)
			return
		while not game._social_events.has(0):
			await process_frame
			if Time.get_ticks_msec()>deadline:
				push_error("Maximum voice clip was not received through native socket")
				quit(3)
				return
		if game._social_events[0].get("text","")!="语音 5.0 秒": quit(4); return
		print("LANDLORD_NATIVE_VOICE_RATE_OK rate=",rate," payload_chars=",encoded.length()," accepted_and_received=true")
		await create_timer(1.05).timeout
	app.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("LANDLORD_NATIVE_VOICE_TRANSPORT_OK maximum_seconds=5 rates=2 actual_server=true native_godot=true")
	quit()
