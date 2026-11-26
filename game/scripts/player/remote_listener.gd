class_name RemoteListener
extends Node3D

const COL_PAPER := Color(0.867, 0.839, 0.769, 1.0) # #DDD6C4
const COL_PAPER_DIM := Color(0.612, 0.592, 0.541, 1.0) # #9C978A
const COL_SODIUM := Color(0.890, 0.635, 0.231, 1.0) # #E3A23B
const COL_SIGNAL := Color(0.800, 0.227, 0.180, 1.0) # #CC3A2E
const COL_INK := Color(0.039, 0.047, 0.043, 0.92) # #0A0C0B

var peer_id: String = ""
var callsign: String = "SURVIVOR"
var is_crouching: bool = false
var is_hiding: bool = false
var is_downed: bool = false
var is_caged: bool = false
var is_frozen: bool = false
var wounds: int = 0
var flashlight_on: bool = true

var _target_pos: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _target_pitch: float = 0.0
var _avatar: Node3D = null
var _anim: AnimationPlayer = null
var _name_lbl: Label3D = null
var _beam: SpotLight3D = null
var _voice_player: AudioStreamPlayer3D = null
var _walk_anim_name: String = ""
var _idle_anim_name: String = ""


func _ready() -> void:
	_avatar = AssetLibrary.instantiate_model("survivor_hazmat")
	add_child(_avatar)
	_anim = AssetLibrary.find_animation_player(_avatar)
	if _anim != null:
		for aname in _anim.get_animation_list():
			var low := aname.to_lower()
			var a := _anim.get_animation(aname)
			if a != null:
				a.loop_mode = Animation.LOOP_LINEAR
			if low.contains("walk"):
				_walk_anim_name = aname
			elif low.contains("idle"):
				_idle_anim_name = aname
		if not _idle_anim_name.is_empty():
			_anim.play(_idle_anim_name)

	_name_lbl = Label3D.new()
	_name_lbl.position = Vector3(0, 2.04, 0)
	_name_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_lbl.font_size = 28
	_name_lbl.outline_size = 7
	_name_lbl.outline_modulate = COL_INK
	_name_lbl.modulate = COL_PAPER
	_name_lbl.uppercase = true
	if ResourceLoader.exists("res://assets/fonts/Oswald-Variable.ttf"):
		var oswald := load("res://assets/fonts/Oswald-Variable.ttf") as Font
		if oswald != null:
			var fv := FontVariation.new()
			fv.base_font = oswald
			fv.variation_opentype = {"wght": 600}
			_name_lbl.font = fv
	_name_lbl.text = callsign
	add_child(_name_lbl)

	_beam = SpotLight3D.new()
	_beam.position = Vector3(0, 1.52, -0.22)
	_beam.light_color = Color(1.0, 0.92, 0.76)
	_beam.light_energy = 1.35
	_beam.spot_range = 13.0
	_beam.spot_angle = 32.0
	add_child(_beam)

	var sb := StaticBody3D.new()
	sb.set_meta("interact_type", "ally")
	sb.set_meta("peer_id", peer_id)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.44
	cap.height = 1.65
	cs.shape = cap
	cs.position = Vector3(0, 0.82, 0)
	sb.add_child(cs)
	add_child(sb)

	_voice_player = AudioStreamPlayer3D.new()
	_voice_player.bus = &"Voice3D"
	_voice_player.unit_size = 5.5
	_voice_player.max_distance = 28.0
	_voice_player.position = Vector3(0, 1.55, 0)
	add_child(_voice_player)


func apply_network_state(state: Dictionary) -> void:
	callsign = str(state.get("callsign", callsign))
	if typeof(state.get("pos")) == TYPE_ARRAY and state["pos"].size() >= 3:
		var p: Array = state["pos"]
		var next_pos := Vector3(float(p[0]), float(p[1]), float(p[2]))
		if global_position.distance_to(next_pos) > 5.0:
			global_position = next_pos
		_target_pos = next_pos
	_target_yaw = float(state.get("yaw", _target_yaw))
	_target_pitch = clampf(float(state.get("pitch", _target_pitch)), -1.2, 1.2)
	is_crouching = bool(state.get("crouch", false))
	is_hiding = bool(state.get("hiding", false))
	is_downed = bool(state.get("downed", false))
	is_caged = bool(state.get("caged", false))
	wounds = int(state.get("wounds", 0))
	is_frozen = bool(state.get("frozen", false))
	flashlight_on = bool(state.get("flash", true))


func play_voice_packet(pcm8: PackedByteArray) -> void:
	if _voice_player == null:
		return
	var stream := AcousticBus.decode_network_voice_packet(pcm8)
	if stream != null:
		_voice_player.stream = stream
		_voice_player.play()


func _process(delta: float) -> void:
	visible = not is_hiding
	var move_dist := global_position.distance_to(_target_pos)
	var smooth := 1.0 - exp(-delta * 12.0)
	global_position = global_position.lerp(_target_pos, smooth)
	rotation.y = lerp_angle(rotation.y, _target_yaw, smooth)

	if _beam != null:
		_beam.visible = flashlight_on and not is_hiding and not is_downed
		var beam_y := 1.08 if is_crouching else 1.52
		_beam.position.y = lerpf(_beam.position.y, beam_y, smooth)
		_beam.rotation.x = lerpf(_beam.rotation.x, _target_pitch, smooth)

	if _avatar != null:
		var target_scale := Vector3.ONE
		var target_pos := Vector3.ZERO
		var target_rot_x := 0.0
		if is_downed:
			target_scale = Vector3(1.0, 0.96, 1.0)
			target_pos = Vector3(0.0, 0.16, 0.56)
			target_rot_x = -1.22
		elif is_crouching:
			target_scale = Vector3(1.04, 0.76, 1.04)
			target_pos = Vector3(0.0, 0.0, 0.04)
			target_rot_x = -0.18
		var posture_alpha := 1.0 - exp(-delta * 10.0)
		_avatar.scale = _avatar.scale.lerp(target_scale, posture_alpha)
		_avatar.position = _avatar.position.lerp(target_pos, posture_alpha)
		_avatar.rotation.x = lerpf(_avatar.rotation.x, target_rot_x, posture_alpha)

	if _name_lbl != null:
		var tag := ""
		var lbl_col := COL_PAPER
		if is_downed:
			tag = " · SOS"
			lbl_col = COL_SIGNAL
		elif is_caged:
			tag = " · CAGE"
			lbl_col = COL_SODIUM
		elif wounds > 0:
			lbl_col = COL_SODIUM
		elif is_frozen:
			lbl_col = COL_PAPER_DIM
		_name_lbl.modulate = lbl_col
		_name_lbl.text = callsign + tag
		var lbl_y := 1.05 if is_downed else (1.58 if is_crouching else 2.04)
		_name_lbl.position.y = lerpf(_name_lbl.position.y, lbl_y, 1.0 - exp(-delta * 10.0))

	if _anim != null:
		var want := _walk_anim_name if move_dist > 0.06 else _idle_anim_name
		if not want.is_empty() and _anim.current_animation != want:
			_anim.play(want)
