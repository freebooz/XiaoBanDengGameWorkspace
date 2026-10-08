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
	_bus_name = "LandlordVoiceCapture_%d" % get_instance_id()
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
	_capture.clear_buffer()
	_started_ms = Time.get_ticks_msec()
	_recording = true
	_microphone.play()
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
		last_error = "录音太短，请按住语音按钮说话"
	return payload

static func encode_samples(frames: PackedVector2Array, source_rate: float) -> Dictionary:
	if source_rate <= 0:
		return {}
	var count := mini(int(float(frames.size())*SAMPLE_RATE/source_rate),int(MAX_SECONDS*SAMPLE_RATE))
	if count < SAMPLE_RATE / 10:
		return {}
	var bytes := PackedByteArray()
	bytes.resize(count*2)
	for index in range(count):
		var offset := float(index)*source_rate/SAMPLE_RATE
		var first := mini(int(offset),frames.size()-1)
		var second := mini(first+1,frames.size()-1)
		var sample := frames[first].lerp(frames[second],offset-float(first))
		bytes.encode_s16(index*2,roundi(clampf((sample.x+sample.y)*0.5,-1.0,1.0)*32767.0))
	return {"sample_rate":SAMPLE_RATE,"pcm_base64":Marshalls.raw_to_base64(bytes),"duration_ms":int(float(count)*1000/SAMPLE_RATE)}

static func decode_stream(payload: Dictionary) -> AudioStreamWAV:
	if int(payload.get("sample_rate",0))!=SAMPLE_RATE:
		return null
	var encoded := str(payload.get("pcm_base64",""))
	if encoded.length()>106668:
		return null
	var bytes := Marshalls.base64_to_raw(encoded)
	if bytes.size()<SAMPLE_RATE/5 or bytes.size()>int(MAX_SECONDS*SAMPLE_RATE)*2 or bytes.size()%2!=0:
		return null
	if int(payload.get("duration_ms",0))!=int(float(bytes.size())*500/SAMPLE_RATE):
		return null
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
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
	if is_instance_valid(_microphone): _microphone.stop()
	if is_instance_valid(_playback): _playback.stop()
	var index := AudioServer.get_bus_index(_bus_name)
	if index >= 0: AudioServer.remove_bus(index)
