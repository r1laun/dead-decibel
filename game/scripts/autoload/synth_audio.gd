extends Node

const SAMPLE_RATE := 22050

var clips: Dictionary = {}
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _drone_player: AudioStreamPlayer = null
var _heartbeat_timer: float = 0.0


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
	_drone_player.volume_db = -14.0
	add_child(_drone_player)
	if DisplayServer.get_name() != "headless":
		_drone_player.play()


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

	# 1. Dark Facility Ambient Drone (6.0s seamless loop with sub-harmonic room resonance)
	var n := int(SAMPLE_RATE * 6.0)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var xfade := int(SAMPLE_RATE * 0.40)
	var raw_air := PackedFloat32Array()
	raw_air.resize(n + xfade)
	var air_lp := 0.0
	for i in range(n + xfade):
		air_lp = air_lp * 0.93 + rng.randf_range(-1.0, 1.0) * 0.07
		raw_air[i] = air_lp
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var slow_lfo := 0.5 + 0.5 * sin(TAU * t / 6.0)
		var pulse_lfo := 0.5 + 0.5 * sin(TAU * t / 2.0)
		var sub := sin(TAU * 36.0 * t + 0.30 * sin(TAU * t / 6.0)) * 0.36
		var fifth := sin(TAU * 54.0 * t) * 0.22 + sin(TAU * 54.5 * t) * 0.13
		var room_mode := sin(TAU * 108.0 * t) * (0.06 + 0.05 * slow_lfo)
		var cold_hum := sin(TAU * 158.5 * t) * 0.045 * pulse_lfo + sin(TAU * 216.0 * t) * 0.025
		var air := raw_air[i]
		if i < xfade:
			var w := 0.5 - 0.5 * cos(PI * float(i) / float(xfade))
			air = lerpf(raw_air[n + i], raw_air[i], w)
		buf[i] = clampf((sub + fifth + room_mode + cold_hum + air * 0.65) * 0.72, -1.0, 1.0)
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


func play_2d(clip_name: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if DisplayServer.get_name() == "headless" or not clips.has(clip_name):
		return
	for p in _pool_2d:
		if not p.playing:
			p.stream = clips[clip_name]
			p.volume_db = vol_db
			p.pitch_scale = pitch
			p.play()
			return
	_pool_2d[0].stream = clips[clip_name]
	_pool_2d[0].volume_db = vol_db
	_pool_2d[0].pitch_scale = pitch
	_pool_2d[0].play()


func play_3d(clip_name: String, pos: Vector3, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if DisplayServer.get_name() == "headless" or not clips.has(clip_name):
		return
	for p in _pool_3d:
		if not p.playing:
			p.global_position = pos
			p.stream = clips[clip_name]
			p.volume_db = vol_db
			p.pitch_scale = pitch
			p.play()
			return
	_pool_3d[0].global_position = pos
	_pool_3d[0].stream = clips[clip_name]
	_pool_3d[0].volume_db = vol_db
	_pool_3d[0].pitch_scale = pitch
	_pool_3d[0].play()


func update_tension_heartbeat(delta: float, monster_dist: float, in_chase: bool) -> void:
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
		if SaveState.haptics_enabled and OS.get_name() == "Android" and closeness > 0.55:
			Input.vibrate_handheld(int(35.0 * closeness))
