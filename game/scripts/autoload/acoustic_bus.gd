extends Node

signal noise_emitted(world_pos: Vector3, radius: float, source_tag: String)
signal voice_chunk_captured(pcm8_8khz: PackedByteArray, level: float)

const VOICE_SAMPLE_RATE := 8000

var current_noise_level: float = 0.0 # 0..1 smooth HUD Noise Meter
var mic_level: float = 0.0
var ptt_held: bool = false
var mic_available: bool = false

var _listener_pos: Vector3 = Vector3.ZERO
var _mic_player: AudioStreamPlayer = null
var _mic_capture: AudioEffectCapture = null
var _noise_floor: float = 0.015
var _calib_timer: float = 1.5
var _calib_sum: float = 0.0
var _calib_samples: int = 0
var _voice_alert_cd: float = 0.0
var _net_chunk_buf := PackedByteArray()


func _ready() -> void:
	_setup_microphone()


func _exit_tree() -> void:
	_net_chunk_buf.clear()


func _setup_microphone() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var idx := AudioServer.get_bus_index(&"MicCapture")
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, &"MicCapture")
		AudioServer.set_bus_mute(idx, true)
		_mic_capture = AudioEffectCapture.new()
		_mic_capture.buffer_length = 0.25
		AudioServer.add_bus_effect(idx, _mic_capture)
	else:
		_mic_capture = AudioServer.get_bus_effect(idx, 0) as AudioEffectCapture

	if OS.get_name() == "Android":
		if not get_tree().on_request_permissions_result.is_connected(_on_permission_result):
			get_tree().on_request_permissions_result.connect(_on_permission_result)
		if OS.request_permission("android.permission.RECORD_AUDIO"):
			_start_mic_stream()
	else:
		_start_mic_stream()


func _on_permission_result(permission: String, granted: bool) -> void:
	if permission == "android.permission.RECORD_AUDIO" and granted:
		_calib_timer = 1.5
		_calib_sum = 0.0
		_calib_samples = 0
		_start_mic_stream()


func _start_mic_stream() -> void:
	if _mic_player != null:
		_mic_player.stop()
		_mic_player.stream = AudioStreamMicrophone.new()
		_mic_player.play()
		mic_available = true
		return
	_mic_player = AudioStreamPlayer.new()
	_mic_player.bus = &"MicCapture"
	_mic_player.stream = AudioStreamMicrophone.new()
	add_child(_mic_player)
	_mic_player.play()
	mic_available = true


func set_listener_position(pos: Vector3) -> void:
	_listener_pos = pos


func emit_noise(world_pos: Vector3, radius: float, hud_spike: float = 0.5, source_tag: String = "action") -> void:
	current_noise_level = maxf(current_noise_level, clampf(hud_spike, 0.0, 1.0))
	noise_emitted.emit(world_pos, radius, source_tag)


func decode_network_voice_packet(pcm8: PackedByteArray) -> AudioStreamWAV:
	if pcm8.is_empty():
		return null
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = VOICE_SAMPLE_RATE
	wav.stereo = false
	var out := PackedByteArray()
	out.resize(pcm8.size() * 2)
	for i in range(pcm8.size()):
		var s := (float(pcm8[i]) - 128.0) / 128.0
		out.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	wav.data = out
	return wav


func _process(delta: float) -> void:
	current_noise_level = move_toward(current_noise_level, 0.0, delta * 0.68)
	_voice_alert_cd = maxf(0.0, _voice_alert_cd - delta)
	_process_microphone(delta)


func _process_microphone(delta: float) -> void:
	var gate_open := false
	if SaveState.mic_mode == SaveState.MIC_AUTO:
		gate_open = true
	elif SaveState.mic_mode == SaveState.MIC_PTT:
		gate_open = ptt_held

	var raw_rms := 0.0
	if _mic_capture != null and _mic_capture.get_frames_available() > 0:
		var n_avail := _mic_capture.get_frames_available()
		var frames := _mic_capture.get_buffer(n_avail)
		var sum_sq := 0.0
		var mix_rate := maxf(8000.0, AudioServer.get_mix_rate())
		var step := maxi(1, int(round(mix_rate / float(VOICE_SAMPLE_RATE))))
		for i in range(frames.size()):
			var mono := (frames[i].x + frames[i].y) * 0.5
			sum_sq += mono * mono
			if gate_open and (i % step == 0) and mic_level > 0.08:
				var u8 := clampi(int((clampf(mono, -1.0, 1.0) * 0.5 + 0.5) * 255.0), 0, 255)
				_net_chunk_buf.append(u8)
		if frames.size() > 0:
			raw_rms = sqrt(sum_sq / float(frames.size()))

	if _calib_timer > 0.0:
		_calib_timer -= delta
		if raw_rms > 0.0:
			_calib_sum += raw_rms
			_calib_samples += 1
		if _calib_timer <= 0.0 and _calib_samples > 4:
			_noise_floor = clampf((_calib_sum / float(_calib_samples)) * 1.75, 0.01, 0.08)

	var gated := maxf(0.0, raw_rms - _noise_floor) if gate_open else 0.0
	mic_level = lerpf(mic_level, clampf(gated * 8.5, 0.0, 1.0), clampf(delta * 14.0, 0.0, 1.0))

	if mic_level > 0.15:
		current_noise_level = maxf(current_noise_level, mic_level * 0.9)
	# Loud speaking/shouting alerts Specimen-07!
	if mic_level > 0.42 and _voice_alert_cd <= 0.0 and _listener_pos != Vector3.ZERO:
		_voice_alert_cd = 0.65
		emit_noise(_listener_pos, lerpf(9.0, 22.0, mic_level), mic_level, "voice")

	if _net_chunk_buf.size() >= 960:
		var pkt := _net_chunk_buf.duplicate()
		_net_chunk_buf.clear()
		voice_chunk_captured.emit(pkt, mic_level)
