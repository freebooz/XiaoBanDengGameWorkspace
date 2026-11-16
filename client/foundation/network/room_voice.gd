extends Node
## Real microphone input and bounded room voice clips. No recording starts until
## the player holds the voice button; recording data is cleared after submission.

const SAMPLE_RATE := 8000
const MAX_SECONDS := 5.0
var last_error := ""
var _bus_name := ""
var _capture: AudioEffectCapture
var _microphone: AudioStreamPlayer
var _playback: AudioStreamPlayer
var _recording := false
var _started_ms := 0

func configure(parent: Node) -> void:
	parent.add_child(self)
	_bus_name = "RoomVoiceCapture_%d" % get_instance_id()
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index,_bus_name)
	AudioServer.set_bus_mute(index,true)
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = MAX_SECONDS + 1.0
	AudioServer.add_bus_effect(index,_capture)
	_microphone = AudioStreamPlayer.new()
	_microphone.bus = _bus_name
	_microphone.stream = AudioStreamMicrophone.new()
	add_child(_microphone)
	_playback = AudioStreamPlayer.new()
	add_child(_playback)

func start_recording() -> Error:
	last_error = ""
	if OS.has_feature("android") and not OS.get_granted_permissions().has("android.permission.RECORD_AUDIO"):
		OS.request_permission("android.permission.RECORD_AUDIO")
		last_error = "请允许麦克风权限，再按住语音按钮"
		return ERR_UNAUTHORIZED
	if DisplayServer.get_name()=="headless" or AudioServer.get_input_device_list().is_empty():
		last_error = "当前设备没有可用麦克风"
		return ERR_UNAVAILABLE
	if not is_instance_valid(_microphone):
		last_error = "语音尚未就绪"
		return ERR_UNCONFIGURED
	if not ProjectSettings.get_setting("audio/driver/enable_input", false) or AudioServer.get_driver_name() == "Dummy":
		last_error = "麦克风输入未启用，请检查设备音频设置"
		return ERR_UNAVAILABLE
	_capture.clear_buffer()
	_started_ms = Time.get_ticks_msec()
	_recording = true
	_microphone.play()
	var playback := _microphone.get_stream_playback()
	if playback == null or not playback.is_playing():
		_recording = false
		_microphone.stop()
		last_error = "无法启动麦克风，请检查权限和输入设备"
		return ERR_CANT_OPEN
	return OK

func stop_recording() -> Dictionary:
	if not _recording:
		return {}
	_recording = false
	_microphone.stop()
	var frames := _capture.get_buffer(_capture.get_frames_available())
	_capture.clear_buffer()
	if frames.is_empty():
		last_error = "未收到麦克风声音，请检查系统麦克风权限"
		return {}
	var payload := encode_samples(frames,AudioServer.get_mix_rate())
	if payload.is_empty():
		last_error = "录音太短，请按住语音按钮说话" if frames.size() < AudioServer.get_mix_rate() / 10.0 else "没有收到有效声音，请检查麦克风静音、权限和输入设备"
	return payload

static func encode_samples(frames: PackedVector2Array, source_rate: float) -> Dictionary:
	if source_rate <= 0:
		return {}
	var count := mini(int(float(frames.size())*SAMPLE_RATE/source_rate),int(MAX_SECONDS*SAMPLE_RATE))
	if count < SAMPLE_RATE / 10:
		return {}
	# Some stereo capture devices provide opposite-polarity channels. Averaging
	# them unconditionally discards the voice; retain the stronger channel only
	# when the downmix would cancel most of the original signal.
	var left_energy := 0.0
	var right_energy := 0.0
	var mono_energy := 0.0
	for frame in frames:
		left_energy += frame.x * frame.x
		right_energy += frame.y * frame.y
		mono_energy += pow((frame.x + frame.y) * 0.5, 2.0)
	var use_channel := mono_energy < maxf(left_energy, right_energy) * 0.0625
	var use_left := left_energy >= right_energy
	var bytes := PackedByteArray()
	bytes.resize(count*2)
	var peak := 0
	for index in range(count):
		var offset := float(index)*source_rate/SAMPLE_RATE
		var first := mini(int(offset),frames.size()-1)
		var second := mini(first+1,frames.size()-1)
		var sample := frames[first].lerp(frames[second],offset-float(first))
		var mono := (sample.x if use_left else sample.y) if use_channel else (sample.x + sample.y) * 0.5
		var encoded := roundi(clampf(mono,-1.0,1.0)*32767.0)
		peak = maxi(peak, absi(encoded))
		bytes.encode_s16(index*2, encoded)
	# Zero input is not a successful recording. Do not impose a speech-volume
	# gate: even very quiet nonzero input remains valid.
	if peak == 0:
		return {}
	return {"sample_rate":SAMPLE_RATE,"pcm_base64":Marshalls.raw_to_base64(bytes),"duration_ms":int(float(count)*1000/SAMPLE_RATE)}

static func decode_stream(payload: Dictionary) -> AudioStreamWAV:
	var rate := int(payload.get("sample_rate",0))
	if rate not in [8000,16000]:
		return null
	var encoded := str(payload.get("pcm_base64",""))
	if encoded.length()>int(MAX_SECONDS*rate)*8/3+4:
		return null
	var bytes := Marshalls.base64_to_raw(encoded)
	if bytes.size()<rate/5 or bytes.size()>int(MAX_SECONDS*rate)*2 or bytes.size()%2!=0:
		return null
	if int(payload.get("duration_ms",0))!=int(float(bytes.size())*500/rate):
		return null
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	return stream

func play(payload: Dictionary) -> Error:
	var stream := decode_stream(payload)
	if stream == null or not is_instance_valid(_playback):
		last_error = "语音数据无效"
		return ERR_INVALID_DATA
	_playback.stream = stream
	_playback.play()
	return OK

func set_playback_enabled(enabled: bool) -> void:
	if is_instance_valid(_playback):
		_playback.volume_db = 0.0 if enabled else -80.0

func _exit_tree() -> void:
	if is_instance_valid(_microphone):
		_microphone.stop()
		_microphone.stream = null
	if is_instance_valid(_playback):
		_playback.stop()
		_playback.stream = null
	var index := AudioServer.get_bus_index(_bus_name)
	if index >= 0: AudioServer.remove_bus(index)
