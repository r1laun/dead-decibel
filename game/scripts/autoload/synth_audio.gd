extends Node

const SAMPLE_RATE := 22050

var clips: Dictionary = {}
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d_cursor: int = 0
var _pool_3d_cursor: int = 0
var _drone_player: AudioStreamPlayer = null
var _menu_music_player: AudioStreamPlayer = null
var _chase_music_player: AudioStreamPlayer = null
var _heartbeat_timer: float = 0.0
var _haptic_cd: float = 0.0


func _ready() -> void:
	_ensure_audio_buses()
	_build_all_clips()
	for _i in range(8):
		var p2 := AudioStreamPlayer.new()
		p2.bus = &"WorldSFX"
		add_child(p2)
		_pool_2d.append(p2)
	for _i in range(16):
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = &"WorldSFX"
		p3.unit_size = 5.0
		p3.max_distance = 28.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_pool_3d.append(p3)

	_drone_player = AudioStreamPlayer.new()
	_drone_player.bus = &"WorldSFX"
	_drone_player.stream = clips["ambient_drone"]
	_drone_player.volume_db = -24.0
	add_child(_drone_player)
	if DisplayServer.get_name() != "headless":
		_drone_player.play()

	_menu_music_player = AudioStreamPlayer.new()
	_menu_music_player.bus = &"Master"
	_menu_music_player.stream = clips["menu_theme"]
	_menu_music_player.volume_db = -10.5
	add_child(_menu_music_player)

	_chase_music_player = AudioStreamPlayer.new()
	_chase_music_player.bus = &"Master"
	_chase_music_player.stream = clips["chase_theme"]
	_chase_music_player.volume_db = -80.0
	add_child(_chase_music_player)


func set_menu_music(enabled: bool) -> void:
	if DisplayServer.get_name() == "headless" or _menu_music_player == null or not is_instance_valid(_menu_music_player):
		return
	if enabled:
		if _chase_music_player != null and is_instance_valid(_chase_music_player) and _chase_music_player.playing:
			_chase_music_player.stop()
			_chase_music_player.volume_db = -80.0
			_chase_music_player.pitch_scale = 1.0
		if not _menu_music_player.playing:
			_menu_music_player.play()
	else:
		if _menu_music_player.playing:
			_menu_music_player.stop()


func _ensure_audio_buses() -> void:
	if AudioServer.get_bus_index(&"WorldSFX") == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, &"WorldSFX")
		AudioServer.set_bus_send(idx, &"Master")
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.58
		rev.damping = 0.48
		rev.wet = 0.22
		rev.dry = 0.88
		AudioServer.add_bus_effect(idx, rev)

	if AudioServer.get_bus_index(&"Voice3D") == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, &"Voice3D")
		AudioServer.set_bus_send(idx, &"Master")
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.65
		rev.damping = 0.40
		rev.wet = 0.26
		AudioServer.add_bus_effect(idx, rev)


func _make_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _build_all_clips() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90707

	# 1. Quiet Underground Concrete Facility Hum (6.0s seamless loop, zero wind/white-noise)
	var n := int(SAMPLE_RATE * 6.0)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var slow_lfo := 0.5 + 0.5 * sin(TAU * t / 6.0)
		var vent_lfo := 0.5 + 0.5 * sin(TAU * t / 3.0)
		# Soft 50 Hz fluorescent lamp ballast hum + gentle 100/150 Hz harmonics
		var ballast := sin(TAU * 50.0 * t) * 0.24 + sin(TAU * 100.0 * t) * 0.08 + sin(TAU * 150.0 * t) * 0.025
		# Distant ventilation resonance (low sub-room harmonic, zero noise)
		var vent_res := sin(TAU * 36.0 * t) * (0.18 + 0.06 * slow_lfo) + sin(TAU * 72.0 * t) * (0.09 + 0.03 * vent_lfo)
		# Faint metallic pipe undertone
		var pipe_hum := sin(TAU * 108.0 * t) * (0.045 + 0.025 * slow_lfo) + sin(TAU * 162.0 * t) * 0.018
		buf[i] = clampf((ballast + vent_res + pipe_hum) * 0.55, -1.0, 1.0)
	clips["ambient_drone"] = _make_wav(buf, true)

	# 2. Crisp Analog Instrument Relay Click (tactile Bakelite toggle)
	n = int(SAMPLE_RATE * 0.048)
	buf = PackedFloat32Array()
	buf.resize(n)
	var click_lp := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		click_lp = click_lp * 0.55 + rng.randf_range(-1.0, 1.0) * 0.45
		var body := sin(TAU * (195.0 - t * 1400.0) * t) * exp(-t * 145.0) * 0.52
		var contact := (sin(TAU * 1850.0 * t) * 0.34 + sin(TAU * 3150.0 * t) * 0.20) * exp(-t * 255.0)
		var snap := click_lp * exp(-t * 280.0) * 0.42
		var rebound := sin(TAU * 340.0 * maxf(0.0, t - 0.012)) * exp(-maxf(0.0, t - 0.012) * 210.0) * (0.28 if t > 0.012 else 0.0)
		buf[i] = clampf((body + contact + snap + rebound) * 0.76, -1.0, 1.0)
	clips["ui_click"] = _make_wav(buf)

	# 3. Tile Footstep & Soft Crouch Step
	n = int(SAMPLE_RATE * 0.16)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var thud := sin(TAU * (135.0 - t * 420.0) * t) * exp(-t * 34.0)
		var grit := rng.randf_range(-1.0, 1.0) * exp(-t * 58.0) * 0.45
		buf[i] = (thud + grit) * 0.65
	clips["step_tile"] = _make_wav(buf)

	# 4. Heavy Monster Step + Rusted Shackle Clink
	n = int(SAMPLE_RATE * 0.34)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var boom := sin(TAU * (78.0 - t * 140.0) * t) * exp(-t * 15.0) * 0.85
		var chain := (sin(TAU * 2480.0 * t) + sin(TAU * 3690.0 * t)) * exp(-maxf(0.0, t - 0.04) * 36.0) * (0.28 if t > 0.04 else 0.0)
		buf[i] = clampf(boom + chain, -1.0, 1.0)
	clips["monster_step"] = _make_wav(buf)

	# 5. Monster Alert Snarl (heard player noise!)
	n = int(SAMPLE_RATE * 0.85)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := sin(minf(1.0, t / 0.12) * PI * 0.5) * exp(-t * 2.4)
		var growl := sin(TAU * (112.0 + 18.0 * sin(TAU * 24.0 * t)) * t) * 0.65
		var rasp := rng.randf_range(-1.0, 1.0) * (0.5 + 0.5 * sin(TAU * 32.0 * t)) * 0.45
		buf[i] = (growl + rasp) * env * 0.88
	clips["monster_snarl"] = _make_wav(buf)

	# 6. Monster Chase Roar / Stinger
	n = int(SAMPLE_RATE * 1.15)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 1.8)
		var screech := sin(TAU * (290.0 + 95.0 * sin(TAU * 17.0 * t) - t * 80.0) * t) * 0.55
		var sub := sin(TAU * 72.0 * t) * 0.55
		var grit := rng.randf_range(-1.0, 1.0) * 0.35
		buf[i] = clampf((screech + sub + grit) * env, -1.0, 1.0)
	clips["monster_roar"] = _make_wav(buf)

	# 7. Brutal Catch Slam (Day End / Caught)
	n = int(SAMPLE_RATE * 0.95)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var hit := sin(TAU * (95.0 - t * 65.0) * t) * exp(-t * 6.5) * 0.95
		var crunch := rng.randf_range(-1.0, 1.0) * exp(-t * 11.0) * 0.75
		buf[i] = clampf(hit + crunch, -1.0, 1.0)
	clips["catch_slam"] = _make_wav(buf)

	# 8. Heartbeat Lub-Dub
	n = int(SAMPLE_RATE * 0.38)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var lub := sin(TAU * 54.0 * t) * exp(-t * 24.0)
		var dub := sin(TAU * 62.0 * maxf(0.0, t - 0.16)) * exp(-maxf(0.0, t - 0.16) * 28.0) * (0.85 if t > 0.16 else 0.0)
		buf[i] = (lub + dub) * 0.85
	clips["heartbeat"] = _make_wav(buf)

	# 9. Door Creak Open / Close
	n = int(SAMPLE_RATE * 0.48)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var sq := sin(TAU * (320.0 + 60.0 * sin(TAU * 5.0 * t)) * t) * exp(-t * 6.5) * 0.35
		var latch := rng.randf_range(-1.0, 1.0) * exp(-t * 40.0) * 0.65
		buf[i] = sq + latch
	clips["door_creak"] = _make_wav(buf)

	# 10. Metal Locker Door Clang
	n = int(SAMPLE_RATE * 0.42)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var met := (sin(TAU * 540.0 * t) * 0.5 + sin(TAU * 1180.0 * t) * 0.35) * exp(-t * 14.0)
		var rattle := rng.randf_range(-1.0, 1.0) * exp(-t * 28.0) * 0.45
		buf[i] = (met + rattle) * 0.72
	clips["locker_clang"] = _make_wav(buf)

	# 11. Drawer Slide & Item Pickup
	n = int(SAMPLE_RATE * 0.28)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		buf[i] = rng.randf_range(-1.0, 1.0) * exp(-t * 14.0) * 0.45 + sin(TAU * 420.0 * t) * exp(-t * 25.0) * 0.25
	clips["drawer_slide"] = _make_wav(buf)

	n = int(SAMPLE_RATE * 0.14)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		buf[i] = (sin(TAU * 720.0 * t) * 0.5 + sin(TAU * 1080.0 * t) * 0.4) * exp(-t * 28.0)
	clips["item_pickup"] = _make_wav(buf)

	# 12. Heavy Tool Drop Clatter & Decoy Bottle Shatter!
	n = int(SAMPLE_RATE * 0.55)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var ring1 := sin(TAU * 1420.0 * t) * exp(-t * 12.0) * 0.55
		var ring2 := sin(TAU * 2190.0 * maxf(0.0, t - 0.11)) * exp(-maxf(0.0, t - 0.11) * 16.0) * (0.45 if t > 0.11 else 0.0)
		buf[i] = clampf(ring1 + ring2 + rng.randf_range(-0.3, 0.3) * exp(-t * 25.0), -1.0, 1.0)
	clips["item_clatter"] = _make_wav(buf)

	n = int(SAMPLE_RATE * 0.72)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var crash := rng.randf_range(-1.0, 1.0) * exp(-t * 9.0) * 0.85
		var shards := (sin(TAU * 3800.0 * t) + sin(TAU * 5100.0 * t) + sin(TAU * 6300.0 * t)) * exp(-t * 14.0) * 0.32
		buf[i] = clampf(crash + shards, -1.0, 1.0)
	clips["bottle_shatter"] = _make_wav(buf)

	# 13. Escape Locks: Crowbar Plank Rip, Wire Snip, Generator Power, Padlock, Blast Gate
	n = int(SAMPLE_RATE * 0.68)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var crack := rng.randf_range(-1.0, 1.0) * (0.6 + 0.4 * sin(TAU * 42.0 * t)) * exp(-t * 6.0)
		var thump := sin(TAU * 115.0 * maxf(0.0, t - 0.25)) * exp(-maxf(0.0, t - 0.25) * 16.0) * (0.8 if t > 0.25 else 0.0)
		buf[i] = clampf(crack * 0.75 + thump, -1.0, 1.0)
	clips["plank_rip"] = _make_wav(buf)

	n = int(SAMPLE_RATE * 0.30)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var zap := (sin(TAU * 1950.0 * t) + rng.randf_range(-0.9, 0.9)) * exp(-t * 22.0)
		buf[i] = clampf(zap * 0.85, -1.0, 1.0)
	clips["wire_snip"] = _make_wav(buf)

	n = int(SAMPLE_RATE * 1.1)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var freq := 65.0 + t * 145.0
		buf[i] = (sin(TAU * freq * t) * 0.65 + sin(TAU * freq * 2.0 * t) * 0.25) * exp(-t * 1.4)
	clips["generator_on"] = _make_wav(buf)

	n = int(SAMPLE_RATE * 0.35)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		buf[i] = (sin(TAU * 1340.0 * t) + sin(TAU * 1780.0 * t)) * exp(-t * 18.0) * 0.55
	clips["padlock_open"] = _make_wav(buf)

	n = int(SAMPLE_RATE * 0.10)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		buf[i] = sin(TAU * 1250.0 * t) * exp(-t * 28.0) * 0.6
	clips["keypad_beep"] = _make_wav(buf)

	n = int(SAMPLE_RATE * 0.32)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		buf[i] = sin(TAU * 220.0 * t) * exp(-t * 7.0) * 0.7
	clips["keypad_error"] = _make_wav(buf)

	n = int(SAMPLE_RATE * 0.08)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		buf[i] = (sin(TAU * 1600.0 * t) + rng.randf_range(-0.6, 0.6)) * exp(-t * 65.0) * 0.65
	clips["flashlight_click"] = _make_wav(buf)

	n = int(SAMPLE_RATE * 1.6)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var rumble := sin(TAU * 82.0 * t) * 0.55 + rng.randf_range(-0.35, 0.35)
		var chime := sin(TAU * 520.0 * t) * exp(-t * 2.5) * 0.45
		buf[i] = clampf((rumble * exp(-t * 1.1) + chime) * 0.85, -1.0, 1.0)
	clips["victory_airlock"] = _make_wav(buf)

	# 14. Specimen-07 Organic Bone-Click Sonar Burst + Corridor Reverb Tail
	n = int(SAMPLE_RATE * 0.95)
	var echo_dry := PackedFloat32Array()
	echo_dry.resize(n)
	var click_onsets: Array[float] = [0.0, 0.082, 0.154, 0.238]
	var click_scales: Array[float] = [1.00, 1.09, 0.95, 1.14]
	var click_gains: Array[float] = [0.92, 0.78, 0.96, 0.68]
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var sample_val := 0.0
		for ci in range(click_onsets.size()):
			var t0 := click_onsets[ci]
			if t >= t0:
				var dt := t - t0
				if dt < 0.09:
					var ps := click_scales[ci]
					var chirp_f := (2750.0 * ps) * exp(-dt * 42.0) + 680.0
					var chirp := sin(TAU * chirp_f * dt) * exp(-dt * 118.0) * 0.56
					var bone := (sin(TAU * 1160.0 * ps * dt) * 0.42 + sin(TAU * 1940.0 * ps * dt) * 0.26) * exp(-dt * 150.0)
					var crack := rng.randf_range(-1.0, 1.0) * exp(-dt * 265.0) * 0.30
					var throat := sin(TAU * 172.0 * dt) * exp(-dt * 44.0) * 0.20
					sample_val += (chirp + bone + crack + throat) * click_gains[ci]
		echo_dry[i] = clampf(sample_val, -1.0, 1.0)

	buf = PackedFloat32Array()
	buf.resize(n)
	var tap_delays: Array[int] = [507, 919, 1481, 2137]
	var tap_gains: Array[float] = [0.32, 0.24, 0.17, 0.11]
	var rev_lp := 0.0
	for i in range(n):
		var wet := 0.0
		for ti in range(tap_delays.size()):
			var d_idx := i - tap_delays[ti]
			if d_idx >= 0:
				wet += (echo_dry[d_idx] + buf[d_idx] * 0.46) * tap_gains[ti]
		rev_lp = rev_lp * 0.48 + wet * 0.52
		var tail_env := exp(-maxf(0.0, float(i) / SAMPLE_RATE - 0.18) * 3.1)
		buf[i] = clampf(echo_dry[i] * 0.78 + rev_lp * tail_env * 0.72, -1.0, 1.0)
	clips["echolocate_click"] = _make_wav(buf)

	# 15. Broken Glass Footstep Crunch
	n = int(SAMPLE_RATE * 0.32)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var gr := rng.randf_range(-1.0, 1.0) * exp(-t * 16.0) * 0.7
		var hi := (sin(TAU * 4200.0 * t) + sin(TAU * 5600.0 * t)) * exp(-t * 24.0) * 0.35
		buf[i] = clampf(gr + hi, -1.0, 1.0)
	clips["glass_crunch"] = _make_wav(buf)

	# 16. Rusted Wheelchair Metallic Squeak
	n = int(SAMPLE_RATE * 0.46)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var sq := sin(TAU * (1480.0 + 160.0 * sin(TAU * 9.0 * t)) * t) * exp(-t * 6.0) * 0.55
		buf[i] = clampf(sq + rng.randf_range(-0.15, 0.15) * exp(-t * 15.0), -1.0, 1.0)
	clips["wheelchair_squeak"] = _make_wav(buf)

	# 17. Distant PA Intercom Siren Lure
	n = int(SAMPLE_RATE * 1.35)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var tone := 580.0 if fmod(t, 0.45) < 0.22 else 440.0
		buf[i] = (sin(TAU * tone * t) * 0.6 + sin(TAU * tone * 2.0 * t) * 0.2) * exp(-t * 0.7)
	clips["pa_siren"] = _make_wav(buf)

	# 18. Sonic Strobe Flare Ignite & Shriek (stuns Specimen-07!)
	n = int(SAMPLE_RATE * 0.95)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var hiss := rng.randf_range(-1.0, 1.0) * 0.45
		var whistle := sin(TAU * (2850.0 - t * 450.0) * t) * 0.45
		buf[i] = clampf((hiss + whistle) * exp(-t * 1.6), -1.0, 1.0)
	clips["flare_stun"] = _make_wav(buf)

	# 19. Heavy Frenzy Door Smash & Vent Grate Unscrew
	n = int(SAMPLE_RATE * 0.45)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		buf[i] = clampf((sin(TAU * 92.0 * t) * 0.9 + rng.randf_range(-0.8, 0.8)) * exp(-t * 10.0), -1.0, 1.0)
	clips["door_smash"] = _make_wav(buf)

	n = int(SAMPLE_RATE * 0.30)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		buf[i] = (sin(TAU * 680.0 * t) + rng.randf_range(-0.4, 0.4)) * exp(-t * 14.0) * 0.65
	clips["vent_open"] = _make_wav(buf)

	# 20. Visceral Catch Jumpscare Screech (~0.95s layered metallic shriek + sub-bass slam + predator roar)
	n = int(SAMPLE_RATE * 0.95)
	buf = PackedFloat32Array()
	buf.resize(n)
	var js_lp := 0.0
	var peak := 0.001
	var sum_dc := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var atk := clampf(t / 0.008, 0.0, 1.0)
		var rel := clampf((0.95 - t) / 0.07, 0.0, 1.0)
		var env := atk * rel * exp(-t * 1.55)

		# Sub-bass impact slam (98 Hz dropping to 36 Hz)
		var sub_f := 36.0 + 62.0 * exp(-t * 14.0)
		var sub_slam := sin(TAU * sub_f * t) * exp(-t * 5.2) * 0.95
		var sub_drive := tanh(sub_slam * 1.9) * 0.68

		# Layered metallic shriek (FM dissonant sweep + minor-second metallic partials)
		var fm := sin(TAU * 43.0 * t) * (145.0 * exp(-t * 1.8) + 38.0)
		var shriek_f := 1340.0 * exp(-t * 1.15) + 590.0 + fm
		var shriek := sin(TAU * shriek_f * t) * 0.44 + sin(TAU * (shriek_f * 1.065) * t) * 0.32
		var metal_ring := (sin(TAU * 2380.0 * t) * 0.24 + sin(TAU * 3190.0 * t) * 0.16) * exp(-t * 3.4)

		# Guttural predator roar + raspy breath burst
		js_lp = js_lp * 0.62 + rng.randf_range(-1.0, 1.0) * 0.38
		var roar_f := 138.0 + 26.0 * sin(TAU * 27.0 * t) - t * 32.0
		var roar := tanh(sin(TAU * roar_f * t) * 2.1) * 0.48
		var rasp := js_lp * (0.55 + 0.45 * sin(TAU * 36.0 * t)) * 0.52

		var raw := (sub_drive + (shriek + metal_ring + roar + rasp) * env)
		buf[i] = raw
		sum_dc += raw
	var dc_off := sum_dc / float(n)
	for i in range(n):
		buf[i] -= dc_off
		peak = maxf(peak, absf(buf[i]))
	var norm := 0.94 / peak
	for i in range(n):
		buf[i] = clampf(buf[i] * norm, -1.0, 1.0)
	clips["jumpscare_screech"] = _make_wav(buf)

	# 21. Monster Idle Jaw-Click Echo (creepy rapid mandible clicks)
	n = int(SAMPLE_RATE * 0.58)
	var idle_dry := PackedFloat32Array()
	idle_dry.resize(n)
	var idle_onsets: Array[float] = [0.0, 0.068, 0.129, 0.214]
	var idle_freqs: Array[float] = [1680.0, 1920.0, 1510.0, 2080.0]
	var idle_gains: Array[float] = [0.88, 0.72, 0.94, 0.60]
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var val := 0.0
		for ci in range(idle_onsets.size()):
			var dt := t - idle_onsets[ci]
			if dt >= 0.0 and dt < 0.065:
				var f0 := idle_freqs[ci]
				var jaw := sin(TAU * (f0 * exp(-dt * 38.0) + 460.0) * dt) * exp(-dt * 145.0) * 0.58
				var snap := rng.randf_range(-1.0, 1.0) * exp(-dt * 240.0) * 0.36
				var pop := sin(TAU * 185.0 * dt) * exp(-dt * 58.0) * 0.24
				val += (jaw + snap + pop) * idle_gains[ci]
		idle_dry[i] = clampf(val, -1.0, 1.0)
	buf = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var wet := 0.0
		if i >= 613:
			wet += idle_dry[i - 613] * 0.32
		if i >= 1321:
			wet += idle_dry[i - 1321] * 0.19
		buf[i] = clampf(idle_dry[i] * 0.85 + wet * 0.75, -1.0, 1.0)
	clips["monster_click_idle"] = _make_wav(buf)

	# 22. Monster Wet Guttural Breath Rasp + Faint Shackle Clink
	n = int(SAMPLE_RATE * 1.15)
	buf = PackedFloat32Array()
	buf.resize(n)
	var rasp_lp := 0.0
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var inhale_env := sin(minf(1.0, t / 0.35) * PI * 0.5) * exp(-maxf(0.0, t - 0.28) * 2.3)
		rasp_lp = rasp_lp * 0.72 + rng.randf_range(-1.0, 1.0) * 0.28
		var flutter := 0.55 + 0.45 * sin(TAU * (29.0 + 7.0 * sin(TAU * 3.0 * t)) * t)
		var throat := tanh(sin(TAU * (86.0 + 11.0 * sin(TAU * 6.5 * t)) * t) * 1.7) * 0.42
		var wet_air := rasp_lp * flutter * 0.78
		var clink := 0.0
		if t > 0.52:
			var ct := t - 0.52
			clink = (sin(TAU * 2640.0 * ct) * 0.16 + sin(TAU * 3890.0 * ct) * 0.11) * exp(-ct * 24.0)
		buf[i] = clampf((throat + wet_air) * inhale_env * 0.85 + clink, -1.0, 1.0)
	clips["monster_breath_rasp"] = _make_wav(buf)

	# 23. Scary Main Menu Horror Theme (16.0s seamless loop: bowed tritone drone + detuned cold bells + sub heartbeat)
	n = int(SAMPLE_RATE * 16.0)
	var menu_dry := PackedFloat32Array()
	menu_dry.resize(n)
	# Notes: D2 (73.42), Eb2 (77.78), A2 (110.0), Bb2 (116.54), F3 (174.61)
	var note_times: Array[float] = [0.65, 3.10, 5.25, 8.05, 10.35, 12.60, 14.15]
	var note_freqs: Array[float] = [73.42, 174.61, 77.78, 110.00, 116.54, 174.61, 77.78]
	var note_gains: Array[float] = [0.34, 0.22, 0.32, 0.26, 0.28, 0.20, 0.30]
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var swell_1 := 0.55 + 0.45 * sin(TAU * t / 16.0)
		var swell_2 := 0.50 + 0.50 * sin(TAU * t / 8.0 + 1.1)
		# Dark minor-second & tritone bowed string/organ drone (frequencies cycle-aligned to 16.0s)
		var d2_bow := sin(TAU * 73.375 * t + 0.18 * sin(TAU * 0.25 * t)) * 0.20
		var eb2_bow := sin(TAU * 77.75 * t) * (0.07 + 0.10 * swell_2)
		var tritone_bow := sin(TAU * 103.8125 * t) * (0.06 + 0.08 * swell_1)
		var a1_sub := sin(TAU * 55.0 * t) * 0.22
		var shimmer := sin(TAU * 311.125 * t) * (0.015 + 0.020 * swell_1) + sin(TAU * 466.125 * t) * (0.010 * swell_2)

		# Subtle heartbeat sub-pulse (every 1.6s = 10 beats per 16s loop)
		var hb_t := fmod(t, 1.6)
		var hb_lub := sin(TAU * 52.0 * hb_t) * exp(-hb_t * 20.0) * 0.19
		var hb_dub := sin(TAU * 58.0 * maxf(0.0, hb_t - 0.19)) * exp(-maxf(0.0, hb_t - 0.19) * 24.0) * (0.14 if hb_t > 0.19 else 0.0)

		# Sparse detuned cold piano/bell horror notes
		var bell := 0.0
		for ni in range(note_times.size()):
			var dt := t - note_times[ni]
			if dt >= 0.0 and dt < 3.6:
				var f := note_freqs[ni]
				var n_atk := clampf(dt / 0.014, 0.0, 1.0)
				var n_env := n_atk * exp(-dt * 1.45)
				var p1 := sin(TAU * f * dt) * 0.62 + sin(TAU * (f * 1.0055) * dt) * 0.38
				var p2 := sin(TAU * (f * 2.003) * dt) * exp(-dt * 2.4) * 0.24
				var p3 := sin(TAU * (f * 3.01) * dt) * exp(-dt * 4.2) * 0.10
				bell += (p1 + p2 + p3) * n_env * note_gains[ni]

		menu_dry[i] = d2_bow + eb2_bow + tritone_bow + a1_sub + shimmer + hb_lub + hb_dub + bell

	buf = PackedFloat32Array()
	buf.resize(n)
	var m_taps: Array[int] = [1433, 2879, 4421, 6619]
	var m_gains: Array[float] = [0.28, 0.20, 0.14, 0.09]
	var m_lp := 0.0
	var m_peak := 0.001
	for i in range(n):
		var wet := 0.0
		for ti in range(m_taps.size()):
			var src := (i - m_taps[ti] + n) % n
			wet += menu_dry[src] * m_gains[ti]
		m_lp = m_lp * 0.58 + wet * 0.42
		buf[i] = menu_dry[i] * 0.78 + m_lp * 0.56
		m_peak = maxf(m_peak, absf(buf[i]))
	var m_norm := 0.84 / m_peak
	for i in range(n):
		buf[i] = clampf(buf[i] * m_norm, -1.0, 1.0)
	clips["menu_theme"] = _make_wav(buf, true)

	# 24. Monster Alert Jaw Chatter (rapid clicking bone-jaw snap when hearing sound)
	n = int(SAMPLE_RATE * 0.54)
	var chat_dry := PackedFloat32Array()
	chat_dry.resize(n)
	var chat_onsets: Array[float] = [0.0, 0.048, 0.092, 0.146, 0.190, 0.242, 0.304]
	var chat_freqs: Array[float] = [2150.0, 2480.0, 1890.0, 2620.0, 2040.0, 2390.0, 1740.0]
	var chat_gains: Array[float] = [0.95, 0.82, 0.90, 0.78, 0.96, 0.74, 0.65]
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var cval := 0.0
		for ci in range(chat_onsets.size()):
			var dt := t - chat_onsets[ci]
			if dt >= 0.0 and dt < 0.055:
				var f0 := chat_freqs[ci]
				var clack := sin(TAU * (f0 * exp(-dt * 44.0) + 520.0) * dt) * exp(-dt * 165.0) * 0.62
				var bone := rng.randf_range(-1.0, 1.0) * exp(-dt * 270.0) * 0.44
				var rasp := sin(TAU * 225.0 * dt) * exp(-dt * 68.0) * 0.22
				cval += (clack + bone + rasp) * chat_gains[ci]
		chat_dry[i] = clampf(cval, -1.0, 1.0)
	buf = PackedFloat32Array()
	buf.resize(n)
	var c_peak := 0.001
	for i in range(n):
		var wet := 0.0
		if i >= 487:
			wet += chat_dry[i - 487] * 0.30
		if i >= 1093:
			wet += chat_dry[i - 1093] * 0.18
		buf[i] = chat_dry[i] * 0.88 + wet * 0.70
		c_peak = maxf(c_peak, absf(buf[i]))
	var c_norm := 0.90 / c_peak
	for i in range(n):
		buf[i] = clampf(buf[i] * c_norm, -1.0, 1.0)
	clips["monster_chatter"] = _make_wav(buf)

	# 25. Heart-Pounding Horror Chase Loop (4.0s seamless loop: ~150 BPM double-thump + screeching bowed strings + sub-bass dread)
	n = int(SAMPLE_RATE * 4.0)
	var chase_dry := PackedFloat32Array()
	chase_dry.resize(n)
	var chase_lp := 0.0
	var stinger_times: Array[float] = [0.0, 0.80, 1.60, 2.40, 3.20]
	var stinger_roots: Array[float] = [587.0, 622.25, 554.25, 659.25, 622.25]
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		# Beat cycle: 10 beats per 4.0s (0.40s per beat = 150 BPM, seamless wrap)
		var beat_idx := int(floor(t / 0.40))
		var bt := fmod(t, 0.40)

		# Heavy industrial double-thump percussion (primary thump + tight double-kick on even beats)
		var k1_f := 42.0 + 96.0 * exp(-bt * 34.0)
		var kick1 := tanh(sin(TAU * k1_f * bt) * 2.2) * exp(-bt * 12.5) * 0.72
		var kick1_click := rng.randf_range(-1.0, 1.0) * exp(-bt * 95.0) * 0.28
		var kick2 := 0.0
		if bt >= 0.14:
			var bt2 := bt - 0.14
			var double_gain := 0.58 if (beat_idx % 2 == 0) else 0.34
			var k2_f := 46.0 + 82.0 * exp(-bt2 * 38.0)
			kick2 = tanh(sin(TAU * k2_f * bt2) * 2.0) * exp(-bt2 * 16.0) * double_gain

		# Metallic industrial clang / offbeat rail strike
		var off_t := fmod(t + 0.20, 0.40)
		var clang := (sin(TAU * 890.0 * off_t) * 0.35 + sin(TAU * 1345.0 * off_t) * 0.25 + rng.randf_range(-0.5, 0.5)) * exp(-off_t * 28.0) * 0.22

		# Distorted low sub-bass dread pulse (cycle-aligned to 4.0s: 48 Hz, 51 Hz, 96 Hz)
		var pulse_lfo := 0.62 + 0.38 * sin(TAU * 2.5 * t)
		var sub_raw := sin(TAU * 48.0 * t) * 0.58 + sin(TAU * 51.0 * t) * 0.36 + sin(TAU * 96.0 * t) * 0.24
		var sub_dread := tanh(sub_raw * 2.1) * 0.42 * pulse_lfo

		# Screeching dissonant bowed horror strings / metallic violin stingers (Outlast / Insidious anxiety)
		chase_lp = chase_lp * 0.58 + rng.randf_range(-1.0, 1.0) * 0.42
		var strings := 0.0
		for si in range(stinger_times.size()):
			var dt := t - stinger_times[si]
			if dt >= 0.0 and dt < 0.76:
				var sf := stinger_roots[si] * (1.0 + 0.035 * dt)
				var s_env := clampf(dt / 0.035, 0.0, 1.0) * exp(-dt * 2.35) * clampf((0.76 - dt) / 0.06, 0.0, 1.0)
				var bow_fm := sin(TAU * 31.0 * dt) * 18.0 + chase_lp * 28.0
				var v1 := tanh(sin(TAU * (sf + bow_fm) * dt) * 1.8) * 0.42
				var v2 := tanh(sin(TAU * (sf * 1.064 + bow_fm * 0.8) * dt) * 1.7) * 0.34
				var v3 := sin(TAU * (sf * 1.414) * dt) * 0.20
				strings += (v1 + v2 + v3 + chase_lp * 0.16) * s_env * 0.55

		chase_dry[i] = kick1 + kick1_click + kick2 + clang + sub_dread + strings

	buf = PackedFloat32Array()
	buf.resize(n)
	var ch_taps: Array[int] = [701, 1543, 2411]
	var ch_gains: Array[float] = [0.22, 0.14, 0.08]
	var ch_lp := 0.0
	var ch_peak := 0.001
	for i in range(n):
		var wet := 0.0
		for ti in range(ch_taps.size()):
			var src := (i - ch_taps[ti] + n) % n
			wet += chase_dry[src] * ch_gains[ti]
		ch_lp = ch_lp * 0.52 + wet * 0.48
		buf[i] = chase_dry[i] * 0.86 + ch_lp * 0.42
		ch_peak = maxf(ch_peak, absf(buf[i]))
	var ch_norm := 0.90 / ch_peak
	for i in range(n):
		buf[i] = clampf(buf[i] * ch_norm, -1.0, 1.0)
	clips["chase_theme"] = _make_wav(buf, true)


func play_2d(clip_name: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if DisplayServer.get_name() == "headless" or _pool_2d.is_empty() or not clips.has(clip_name):
		return
	for p in _pool_2d:
		if is_instance_valid(p) and not p.playing:
			p.stream = clips[clip_name]
			p.volume_db = vol_db
			p.pitch_scale = pitch
			p.play()
			return
	var fallback := _pool_2d[_pool_2d_cursor % _pool_2d.size()]
	_pool_2d_cursor = (_pool_2d_cursor + 1) % _pool_2d.size()
	if is_instance_valid(fallback):
		fallback.stream = clips[clip_name]
		fallback.volume_db = vol_db
		fallback.pitch_scale = pitch
		fallback.play()


func play_3d(clip_name: String, pos: Vector3, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if DisplayServer.get_name() == "headless" or _pool_3d.is_empty() or not clips.has(clip_name):
		return
	for p in _pool_3d:
		if is_instance_valid(p) and not p.playing:
			p.global_position = pos
			p.stream = clips[clip_name]
			p.volume_db = vol_db
			p.pitch_scale = pitch
			p.play()
			return
	var fallback := _pool_3d[_pool_3d_cursor % _pool_3d.size()]
	_pool_3d_cursor = (_pool_3d_cursor + 1) % _pool_3d.size()
	if is_instance_valid(fallback):
		fallback.global_position = pos
		fallback.stream = clips[clip_name]
		fallback.volume_db = vol_db
		fallback.pitch_scale = pitch
		fallback.play()


func update_tension_heartbeat(delta: float, monster_dist: float, in_chase: bool) -> void:
	_haptic_cd = maxf(0.0, _haptic_cd - maxf(delta, 0.0))
	if monster_dist > 18.0 and not in_chase:
		_heartbeat_timer = 0.0
		return
	var closeness := clampf(1.0 - (monster_dist / 18.0), 0.15, 1.0)
	if in_chase:
		closeness = 1.0
	var interval := lerpf(1.15, 0.42, closeness)
	_heartbeat_timer -= delta
	if _heartbeat_timer <= 0.0:
		_heartbeat_timer = interval
		play_2d("heartbeat", lerpf(-14.0, -2.0, closeness), lerpf(0.95, 1.15, closeness))
		if SaveState.haptics_enabled and OS.get_name() == "Android" and closeness > 0.55 and _haptic_cd <= 0.0:
			_haptic_cd = 0.60
			Input.vibrate_handheld(maxi(25, int(35.0 * closeness)))


func update_chase_music(delta: float, in_chase: bool, monster_dist: float) -> void:
	if DisplayServer.get_name() == "headless" or _chase_music_player == null or not is_instance_valid(_chase_music_player) or _chase_music_player.stream == null:
		return
	var safe_delta := maxf(delta, 0.0)
	if in_chase:
		var prox := clampf(1.0 - (monster_dist / 14.0), 0.0, 1.0)
		var target_vol := lerpf(-9.5, -5.5, prox)
		var target_pitch := lerpf(1.0, 1.08, prox)
		if not _chase_music_player.playing:
			_chase_music_player.volume_db = -24.0
			_chase_music_player.pitch_scale = target_pitch
			_chase_music_player.play()
		var alpha := 1.0 - exp(-safe_delta * 10.0)
		_chase_music_player.volume_db = lerpf(_chase_music_player.volume_db, target_vol, alpha)
		_chase_music_player.pitch_scale = lerpf(_chase_music_player.pitch_scale, target_pitch, alpha)
	else:
		if _chase_music_player.playing:
			if safe_delta >= 0.9:
				_chase_music_player.stop()
				_chase_music_player.volume_db = -80.0
				_chase_music_player.pitch_scale = 1.0
				return
			_chase_music_player.volume_db = move_toward(_chase_music_player.volume_db, -60.0, safe_delta * 30.0)
			_chase_music_player.pitch_scale = lerpf(_chase_music_player.pitch_scale, 1.0, 1.0 - exp(-safe_delta * 3.0))
			if _chase_music_player.volume_db <= -59.5:
				_chase_music_player.stop()
				_chase_music_player.volume_db = -80.0
				_chase_music_player.pitch_scale = 1.0
