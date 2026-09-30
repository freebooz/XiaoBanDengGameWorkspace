extends RefCounted
class_name XbdTurnWarningSound
## XbdTurnWarningSound（小板凳回合提醒音生成器）
## 使用程序生成的短促双音提示，不依赖外部音频资源。
## 正式美术/音频阶段可以替换为专属品牌音效，调用接口保持不变。


static func create_warning_stream(
	first_frequency: float = 660.0,
	second_frequency: float = 880.0,
	duration_seconds: float = 0.34
) -> AudioStreamWAV:
	var mix_rate := 22050
	var sample_count := int(float(mix_rate) * duration_seconds)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	for index in range(sample_count):
		var time_seconds := float(index) / float(mix_rate)
		var phase_ratio := time_seconds / maxf(duration_seconds, 0.001)
		var frequency := first_frequency if phase_ratio < 0.48 else second_frequency
		var envelope := 1.0
		if phase_ratio < 0.10:
			envelope = phase_ratio / 0.10
		elif phase_ratio > 0.82:
			envelope = maxf(0.0, (1.0 - phase_ratio) / 0.18)

		# 中间留一个很短的间隔，形成“叮-叮”双音提醒。
		if phase_ratio > 0.44 and phase_ratio < 0.52:
			envelope = 0.0

		var sample_value := sin(TAU * frequency * time_seconds) * 0.30 * envelope
		var pcm_value := int(clampf(sample_value, -1.0, 1.0) * 32767.0)
		data.encode_s16(index * 2, pcm_value)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream
