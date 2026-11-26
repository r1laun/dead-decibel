class_name MonsterDirector
extends Node3D

signal player_caught_by_stalker
signal stalker_state_changed(new_state: String)
signal echolocation_pulsed(origin: Vector3)
signal door_smashed_nearby(door_pos: Vector3)

const STATE_PATROL := "PATROL"
const STATE_ECHOLOCATE := "ECHOLOCATE"
const STATE_INVESTIGATE := "INVESTIGATE"
const STATE_INSPECT_LOCKER := "INSPECT_LOCKER"
const STATE_CHASE := "CHASE"
const STATE_STUNNED := "STUNNED"
const STATE_COOLDOWN := "COOLDOWN"

var active: bool = false
var state: String = STATE_PATROL
var stalker_node: Node3D = null
var anim_player: AnimationPlayer = null

var nav_nodes: Array[Vector3] = []
var nav_adj: Array = []
var doors_ref: Array[Dictionary] = []
var lockers_ref: Dictionary = {}

var local_player: ListenerPlayer = null
var remote_players: Dictionary = {}

var patrol_speed: float = 2.30
var investigate_speed: float = 3.75
var chase_speed: float = 5.05
var hearing_multiplier: float = 1.0

var _aura_light: OmniLight3D = null
var _jumpscare_face_light: OmniLight3D = null
var _jumpscare_active: bool = false
var _aura_phase: float = 0.0
var _current_path: Array[Vector3] = []
var _goal_pos: Vector3 = Vector3.ZERO
var _state_timer: float = 0.0
var _step_accum: float = 0.0
var _saw_player_enter_locker_id: String = ""
var _inspect_locker_id: String = ""
var _inspect_grace_timer: float = 0.0
var _echolocate_cooldown: float = 11.0
var _patrol_leg_counter: int = 0
var _last_patrol_idx: int = -1
var _post_chase_sweeps_left: int = 0
var _last_sweep_idx: int = -1
var _net_sync_timer: float = 0.0
var _last_echo_time_sec: float = -99.0

var _anim_map: Dictionary = {
	"idle": "",
	"walk": "",
	"run": "",
	"attack": ""
}


func _ready() -> void:
	AcousticBus.noise_emitted.connect(_on_local_noise)


func clear_stalker() -> void:
	active = false
	_jumpscare_active = false
	if _jumpscare_face_light != null and is_instance_valid(_jumpscare_face_light):
		_jumpscare_face_light.queue_free()
	_jumpscare_face_light = null
	if stalker_node != null and is_instance_valid(stalker_node):
		stalker_node.queue_free()
	stalker_node = null
	anim_player = null
	_aura_light = null
	_current_path.clear()
	_saw_player_enter_locker_id = ""
	_inspect_locker_id = ""
	_post_chase_sweeps_left = 0
	_last_sweep_idx = -1
	state = STATE_PATROL


func spawn_stalker(
	spawn_pos: Vector3,
	difficulty: int,
	p_nav_nodes: Array[Vector3],
	p_nav_adj: Array,
	p_doors: Array[Dictionary],
	p_lockers: Dictionary
) -> void:
	clear_stalker()
	nav_nodes = p_nav_nodes
	nav_adj = p_nav_adj
	doors_ref = p_doors
	lockers_ref = p_lockers

	if difficulty == SaveState.DIFF_PRACTICE:
		active = false
		return

	if difficulty == SaveState.DIFF_NIGHTMARE:
		patrol_speed = 2.75
		investigate_speed = 4.25
		chase_speed = 5.50
		hearing_multiplier = 1.35
	else:
		patrol_speed = 2.28
		investigate_speed = 3.68
		chase_speed = 4.95
		hearing_multiplier = 1.0

	stalker_node = AssetLibrary.instantiate_model("monster_stalker")
	stalker_node.position = spawn_pos
	add_child(stalker_node)

	var aura := OmniLight3D.new()
	aura.position = Vector3(0, 1.95, -0.25)
	aura.light_color = Color(0.85, 0.12, 0.10)
	aura.light_energy = 0.35
	aura.omni_range = 3.4
	stalker_node.add_child(aura)
	_aura_light = aura
	_aura_phase = 0.0

	anim_player = AssetLibrary.find_animation_player(stalker_node)
	if anim_player != null:
		for aname in anim_player.get_animation_list():
			var low := aname.to_lower()
			var anim := anim_player.get_animation(aname)
			if anim != null and not low.contains("attack"):
				anim.loop_mode = Animation.LOOP_LINEAR
			if low.contains("idle"):
				_anim_map["idle"] = aname
			elif low.contains("walk"):
				_anim_map["walk"] = aname
			elif low.contains("run"):
				_anim_map["run"] = aname
			elif low.contains("attack"):
				_anim_map["attack"] = aname
		_play_anim("walk")

	active = true
	state = STATE_PATROL
	_echolocate_cooldown = 10.0
	_patrol_leg_counter = 0
	_post_chase_sweeps_left = 0
	_last_sweep_idx = -1
	_pick_next_patrol_target()


func reset_after_catch(retreat_pos: Vector3) -> void:
	if not active or stalker_node == null:
		return
	end_jumpscare_pose()
	stalker_node.global_position = retreat_pos
	_saw_player_enter_locker_id = ""
	_inspect_locker_id = ""
	_post_chase_sweeps_left = 0
	_last_sweep_idx = -1
	state = STATE_COOLDOWN
	_state_timer = 4.2
	_current_path.clear()
	_play_anim("idle")
	stalker_state_changed.emit(state)


func trigger_jumpscare_pose(cam: Camera3D) -> void:
	if stalker_node == null or not is_instance_valid(stalker_node) or cam == null or not is_instance_valid(cam):
		return
	_jumpscare_active = true
	state = STATE_COOLDOWN
	_state_timer = 3.5
	_current_path.clear()
	_saw_player_enter_locker_id = ""
	_inspect_locker_id = ""

	var cam_pos := cam.global_position
	var cam_fwd := -cam.global_transform.basis.z
	var horiz_fwd := Vector3(cam_fwd.x, 0.0, cam_fwd.z)
	if horiz_fwd.length_squared() < 0.0001:
		horiz_fwd = Vector3(0.0, 0.0, -1.0)
	else:
		horiz_fwd = horiz_fwd.normalized()

	var target_pos := cam_pos + horiz_fwd * 0.78
	target_pos.y = cam_pos.y - 1.92
	stalker_node.global_position = target_pos

	var to_cam := cam_pos - target_pos
	stalker_node.rotation.y = atan2(-to_cam.x, -to_cam.z)

	if anim_player != null and is_instance_valid(anim_player):
		anim_player.speed_scale = 1.6
		var atk_name: String = _anim_map.get("attack", "")
		if not atk_name.is_empty():
			anim_player.stop()
			anim_player.play(atk_name, 0.04)

	if _jumpscare_face_light != null and is_instance_valid(_jumpscare_face_light):
		_jumpscare_face_light.queue_free()
	var face_light := OmniLight3D.new()
	face_light.position = Vector3(0.0, 1.92, -0.45)
	face_light.light_color = Color(1.0, 0.28, 0.14)
	face_light.light_energy = 2.6
	face_light.omni_range = 2.8
	stalker_node.add_child(face_light)
	_jumpscare_face_light = face_light


func end_jumpscare_pose() -> void:
	_jumpscare_active = false
	if _jumpscare_face_light != null and is_instance_valid(_jumpscare_face_light):
		_jumpscare_face_light.queue_free()
	_jumpscare_face_light = null
	if anim_player != null and is_instance_valid(anim_player):
		anim_player.speed_scale = 1.0


func stun_with_flare(flare_pos: Vector3, stun_radius: float = 10.5) -> bool:
	if not active or stalker_node == null:
		return false
	if stalker_node.global_position.distance_to(flare_pos) <= stun_radius:
		_saw_player_enter_locker_id = ""
		_inspect_locker_id = ""
		_post_chase_sweeps_left = 0
		_last_sweep_idx = -1
		_current_path.clear()
		state = STATE_STUNNED
		_state_timer = 5.5
		SynthAudio.play_3d("monster_roar", stalker_node.global_position + Vector3(0, 1.8, 0), 1.5, 1.25)
		stalker_state_changed.emit(state)
		return true
	else:
		# Even if far away, the loud flare shriek attracts him from afar!
		_evaluate_hearing(flare_pos, 26.0)
		return false


func trigger_echolocation() -> void:
	if not active or stalker_node == null or state in [STATE_CHASE, STATE_STUNNED, STATE_COOLDOWN]:
		return
	state = STATE_ECHOLOCATE
	_state_timer = 1.75
	_echolocate_cooldown = randf_range(12.5, 17.5)
	_last_echo_time_sec = Time.get_ticks_msec() * 0.001
	SynthAudio.play_3d("echolocate_click", stalker_node.global_position + Vector3(0, 1.85, 0), 1.5)
	echolocation_pulsed.emit(stalker_node.global_position)
	stalker_state_changed.emit(state)


func notify_player_hid_in_locker(locker_id: String, player_pos: Vector3) -> void:
	if not active or stalker_node == null:
		return
	var dist := stalker_node.global_position.distance_to(player_pos)
	if state == STATE_CHASE and dist < 8.0 and _has_line_of_sight(player_pos + Vector3(0, 1.2, 0)):
		_saw_player_enter_locker_id = locker_id
	else:
		_saw_player_enter_locker_id = ""


func begin_locker_inspection(locker_id: String) -> void:
	if not active or stalker_node == null or not lockers_ref.has(locker_id):
		return
	_inspect_locker_id = locker_id
	_inspect_grace_timer = 0.85
	_state_timer = 2.6
	_post_chase_sweeps_left = 0
	state = STATE_INSPECT_LOCKER
	var lk: Dictionary = lockers_ref[locker_id]
	var stand_pos: Vector3 = lk["exit_pos"]
	_build_nav_path_to(Vector3(stand_pos.x, 0.0, stand_pos.z))
	SynthAudio.play_3d("monster_snarl", stalker_node.global_position + Vector3(0, 1.8, 0), -1.0, 0.88)
	stalker_state_changed.emit(state)


func on_network_noise(world_pos: Vector3, radius: float) -> void:
	if not active or not NetRelay.is_host:
		return
	_evaluate_hearing(world_pos, radius)


func apply_remote_stalker_state(data: Dictionary) -> void:
	if stalker_node == null or NetRelay.is_host:
		return
	if typeof(data.get("pos")) == TYPE_ARRAY and data["pos"].size() >= 3:
		var p: Array = data["pos"]
		stalker_node.global_position = stalker_node.global_position.lerp(
			Vector3(float(p[0]), float(p[1]), float(p[2])), 0.45
		)
	stalker_node.rotation.y = lerp_angle(stalker_node.rotation.y, float(data.get("yaw", 0.0)), 0.45)
	var new_st := str(data.get("state", state))
	if new_st != state:
		state = new_st
		if state == STATE_ECHOLOCATE:
			_last_echo_time_sec = Time.get_ticks_msec() * 0.001
			echolocation_pulsed.emit(stalker_node.global_position)
		stalker_state_changed.emit(state)
	var anim_key := str(data.get("anim", "walk"))
	_play_anim(anim_key)


func get_distance_to_local_player() -> float:
	if not active or stalker_node == null or local_player == null:
		return 999.0
	return stalker_node.global_position.distance_to(local_player.global_position)


func is_visible_from_point(eye_pos: Vector3) -> bool:
	if not active or stalker_node == null:
		return false
	var target := stalker_node.global_position + Vector3(0, 1.45, 0)
	if eye_pos.distance_to(target) > 20.0:
		return false
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye_pos, target)
	if local_player != null:
		q.exclude = [local_player.get_rid()]
	var hit := space.intersect_ray(q)
	return hit.is_empty()


func has_recent_echolocation_ping() -> bool:
	return (Time.get_ticks_msec() * 0.001 - _last_echo_time_sec) < 1.8


func _on_local_noise(world_pos: Vector3, radius: float, _tag: String) -> void:
	if not NetRelay.room_code.is_empty() and not NetRelay.is_host:
		NetRelay.send_game_event("noise", {
			"pos": [snappedf(world_pos.x, 0.05), snappedf(world_pos.y, 0.05), snappedf(world_pos.z, 0.05)],
			"r": snappedf(radius, 0.1)
		})
		return
	_evaluate_hearing(world_pos, radius)


func _evaluate_hearing(world_pos: Vector3, radius: float) -> void:
	if not active or stalker_node == null or state in [STATE_COOLDOWN, STATE_STUNNED]:
		return
	var dist := stalker_node.global_position.distance_to(world_pos)
	if dist <= radius * hearing_multiplier:
		_goal_pos = Vector3(world_pos.x, 0.0, world_pos.z)
		_build_nav_path_to(_goal_pos)
		if state != STATE_CHASE:
			var prev := state
			_post_chase_sweeps_left = 0
			_last_sweep_idx = -1
			state = STATE_INVESTIGATE
			_state_timer = 5.2
			if prev in [STATE_PATROL, STATE_ECHOLOCATE]:
				SynthAudio.play_3d("monster_snarl", stalker_node.global_position + Vector3(0, 1.8, 0), 0.0)
				stalker_state_changed.emit(state)


func _update_aura_light(delta: float) -> void:
	if _aura_light == null or not is_instance_valid(_aura_light):
		return
	_aura_phase += delta
	var rm := SaveState.reduce_motion
	var target_col := Color(0.85, 0.12, 0.10)
	var target_energy := 0.35
	var target_range := 3.4

	match state:
		STATE_PATROL:
			target_col = Color(0.85, 0.12, 0.10)
			target_range = 3.2
			target_energy = 0.35 if rm else (0.35 + 0.08 * sin(_aura_phase * 2.1))
		STATE_ECHOLOCATE:
			target_col = Color(1.0, 0.36, 0.12)
			target_range = 4.0
			target_energy = 0.72 if rm else (0.58 + 0.38 * absf(sin(_aura_phase * 8.5)))
		STATE_INVESTIGATE, STATE_INSPECT_LOCKER:
			target_col = Color(0.95, 0.22, 0.12)
			target_range = 3.8
			target_energy = 0.65 if rm else (0.65 + 0.14 * sin(_aura_phase * 4.2))
		STATE_CHASE:
			target_col = Color(1.0, 0.07, 0.07)
			target_range = 4.6
			target_energy = 1.15 if rm else (1.15 + 0.25 * sin(_aura_phase * 10.5))
		STATE_STUNNED:
			target_col = Color(0.62, 0.25, 0.20)
			target_range = 2.4
			target_energy = 0.12 if rm else (0.08 + 0.10 * maxf(0.0, sin(_aura_phase * 29.0)))
		STATE_COOLDOWN:
			target_col = Color(0.70, 0.10, 0.10)
			target_range = 2.8
			target_energy = 0.22

	var alpha := 1.0 - exp(-delta * 10.0)
	_aura_light.light_color = _aura_light.light_color.lerp(target_col, alpha)
	_aura_light.light_energy = lerpf(_aura_light.light_energy, target_energy, alpha)
	_aura_light.omni_range = lerpf(_aura_light.omni_range, target_range, alpha)


func _apply_step_tremor() -> void:
	if local_player == null or local_player.is_dead or SaveState.reduce_motion or stalker_node == null:
		return
	var d := stalker_node.global_position.distance_to(local_player.global_position)
	if d <= 9.0:
		var falloff := clampf(1.0 - (d / 9.0), 0.0, 1.0)
		var trauma := falloff * (0.20 if state == STATE_CHASE else 0.11)
		local_player.add_camera_trauma(trauma)


func _enter_post_chase_search() -> void:
	state = STATE_INVESTIGATE
	_post_chase_sweeps_left = randi_range(1, 2)
	_last_sweep_idx = _nearest_nav_idx(stalker_node.global_position) if not nav_nodes.is_empty() else -1
	_state_timer = 1.4
	SynthAudio.play_3d("monster_snarl", stalker_node.global_position + Vector3(0, 1.8, 0), -2.5, 0.85)
	stalker_state_changed.emit(state)


func _pick_next_investigate_sweep_node() -> bool:
	if nav_nodes.is_empty() or stalker_node == null:
		return false
	var cur_idx := _nearest_nav_idx(stalker_node.global_position)
	if cur_idx < 0 or cur_idx >= nav_adj.size():
		return false
	var neighbors: Array = nav_adj[cur_idx]
	if neighbors.is_empty():
		return false

	var candidates: Array[int] = []
	for n_var in neighbors:
		var ni := int(n_var)
		if ni != cur_idx and ni != _last_sweep_idx and nav_nodes[ni].distance_to(_goal_pos) <= 18.5:
			candidates.append(ni)
	if candidates.is_empty():
		for n_var in neighbors:
			var ni := int(n_var)
			if ni != cur_idx:
				candidates.append(ni)
	if candidates.is_empty():
		return false

	var next_idx := candidates[randi() % candidates.size()]
	_last_sweep_idx = cur_idx
	_build_nav_path_to(nav_nodes[next_idx])
	_state_timer = 1.9
	SynthAudio.play_3d("monster_snarl", stalker_node.global_position + Vector3(0, 1.8, 0), -5.0, randf_range(0.78, 0.90))
	return true


func _physics_process(delta: float) -> void:
	if not active or stalker_node == null:
		return

	_update_aura_light(delta)
	if _jumpscare_active:
		return

	if not NetRelay.room_code.is_empty() and not NetRelay.is_host:
		_check_client_proximity_sfx(delta)
		return

	_auto_open_or_smash_doors()

	# 1. STUNNED by Sonic Strobe Flare
	if state == STATE_STUNNED:
		_state_timer -= delta
		_play_anim("idle")
		stalker_node.rotate_y(sin(_state_timer * 11.0) * delta * 3.2)
		if _state_timer <= 0.0:
			state = STATE_PATROL
			_pick_next_patrol_target()
			stalker_state_changed.emit(state)
		_broadcast_stalker_net(delta, "idle")
		return

	# 2. COOLDOWN after catch
	if state == STATE_COOLDOWN:
		_state_timer -= delta
		_play_anim("idle")
		if _state_timer <= 0.0:
			state = STATE_PATROL
			_pick_next_patrol_target()
			stalker_state_changed.emit(state)
		_broadcast_stalker_net(delta, "idle")
		return

	# 3. ECHOLOCATE doorway sonar listening pause
	if state == STATE_ECHOLOCATE:
		_state_timer -= delta
		_play_anim("idle")
		stalker_node.rotate_y(sin(_state_timer * 4.5) * delta * 1.6)
		_check_echolocation_detection()
		if state == STATE_ECHOLOCATE and _state_timer <= 0.0:
			state = STATE_PATROL
			_pick_next_patrol_target()
			stalker_state_changed.emit(state)
		_broadcast_stalker_net(delta, "idle")
		return

	# Periodic Echolocation trigger during Patrol when within medium range
	if state == STATE_PATROL:
		_echolocate_cooldown -= delta
		if _echolocate_cooldown <= 0.0 and get_distance_to_local_player() < 28.0:
			trigger_echolocation()
			return

	# 4. Direct survivor detection (LoS / Flashlight / Touch)
	var sensed_target: Dictionary = _sense_any_survivor()
	if not sensed_target.is_empty():
		var tpos: Vector3 = sensed_target["pos"]
		_goal_pos = Vector3(tpos.x, 0.0, tpos.z)
		_post_chase_sweeps_left = 0
		if state != STATE_CHASE:
			state = STATE_CHASE
			SynthAudio.play_3d("monster_roar", stalker_node.global_position + Vector3(0, 1.8, 0), 2.0)
			stalker_state_changed.emit(state)
		_state_timer = 5.0
		if _has_line_of_sight(tpos + Vector3(0, 1.0, 0)):
			_current_path = [_goal_pos]
		else:
			_build_nav_path_to(_goal_pos)

		if stalker_node.global_position.distance_to(_goal_pos) <= 1.42:
			_play_anim("attack")
			if sensed_target["is_local"]:
				state = STATE_COOLDOWN
				_state_timer = 3.5
				player_caught_by_stalker.emit()
				return
			else:
				NetRelay.send_game_event("stalker_caught_peer", {"target_id": sensed_target["peer_id"]})
				state = STATE_COOLDOWN
				_state_timer = 3.2
				return

	# 5. State machine movement & locker inspection
	var cur_spd := patrol_speed
	var cur_anim := "walk"
	match state:
		STATE_PATROL:
			cur_spd = patrol_speed
			cur_anim = "walk"
			if _current_path.is_empty():
				_pick_next_patrol_target()

		STATE_INVESTIGATE:
			cur_spd = investigate_speed
			cur_anim = "walk"
			if _current_path.is_empty():
				var susp_lid := _find_nearby_occupied_locker(6.2)
				if not susp_lid.is_empty():
					begin_locker_inspection(susp_lid)
					return
				cur_anim = "idle"
				_state_timer -= delta
				stalker_node.rotate_y(sin(_state_timer * 2.4) * delta * 1.4)
				if _state_timer <= 0.0:
					if _post_chase_sweeps_left > 0:
						_post_chase_sweeps_left -= 1
						if _pick_next_investigate_sweep_node():
							cur_anim = "walk"
						else:
							_post_chase_sweeps_left = 0
					if _state_timer <= 0.0 and _post_chase_sweeps_left <= 0:
						state = STATE_PATROL
						_pick_next_patrol_target()
						stalker_state_changed.emit(state)
			elif _post_chase_sweeps_left > 0:
				var close_lid := _find_nearby_occupied_locker(4.0)
				if not close_lid.is_empty():
					begin_locker_inspection(close_lid)
					return

		STATE_INSPECT_LOCKER:
			cur_spd = investigate_speed
			if not lockers_ref.has(_inspect_locker_id):
				state = STATE_PATROL
				_pick_next_patrol_target()
			else:
				var lk: Dictionary = lockers_ref[_inspect_locker_id]
				var stand_p: Vector3 = lk["exit_pos"]
				var d_lk := stalker_node.global_position.distance_to(Vector3(stand_p.x, 0.0, stand_p.z))
				if d_lk <= 1.15:
					_current_path.clear()
					cur_anim = "idle"
					# Face directly into the locker vents!
					var lk_pos := (lk["node"] as Node3D).global_position
					var to_lk := (lk_pos - stalker_node.global_position)
					if Vector2(to_lk.x, to_lk.z).length() > 0.05:
						stalker_node.rotation.y = lerp_angle(stalker_node.rotation.y, atan2(-to_lk.x, -to_lk.z), delta * 8.0)

					_inspect_grace_timer = maxf(0.0, _inspect_grace_timer - delta)
					_state_timer -= delta
					if local_player != null and local_player.is_hiding_in_locker and local_player.current_locker_id == _inspect_locker_id:
						var caught_in_locker := (_saw_player_enter_locker_id == _inspect_locker_id)
						if _inspect_grace_timer <= 0.0 and not local_player.is_holding_breath:
							caught_in_locker = true
						if caught_in_locker:
							_saw_player_enter_locker_id = ""
							_inspect_locker_id = ""
							lk["occupied"] = false
							local_player.exit_locker(stand_p)
							_play_anim("attack")
							state = STATE_COOLDOWN
							_state_timer = 3.5
							player_caught_by_stalker.emit()
							return

					if _state_timer <= 0.0:
						_inspect_locker_id = ""
						state = STATE_PATROL
						_pick_next_patrol_target()
						stalker_state_changed.emit(state)

		STATE_CHASE:
			cur_spd = chase_speed
			cur_anim = "run"
			_state_timer -= delta
			if not _saw_player_enter_locker_id.is_empty() and lockers_ref.has(_saw_player_enter_locker_id):
				var lk2: Dictionary = lockers_ref[_saw_player_enter_locker_id]
				var lk_pos2: Vector3 = lk2["exit_pos"]
				if stalker_node.global_position.distance_to(Vector3(lk_pos2.x, 0, lk_pos2.z)) <= 1.75:
					_saw_player_enter_locker_id = ""
					if local_player != null and local_player.is_hiding_in_locker:
						lk2["occupied"] = false
						local_player.exit_locker(lk_pos2)
						player_caught_by_stalker.emit()
						return
			if _current_path.is_empty():
				var susp := _find_nearby_occupied_locker(6.5)
				if not susp.is_empty():
					begin_locker_inspection(susp)
					return
				if sensed_target.is_empty() or _state_timer <= 0.0:
					_enter_post_chase_search()
					cur_anim = "idle"

	if not _current_path.is_empty() and cur_anim != "idle":
		var wp: Vector3 = _current_path[0]
		var to_wp := Vector3(wp.x - stalker_node.global_position.x, 0.0, wp.z - stalker_node.global_position.z)
		var d := to_wp.length()
		if d < 0.45:
			_current_path.pop_front()
		else:
			var dir := to_wp / d
			stalker_node.global_position += dir * minf(d, cur_spd * delta)
			var want_yaw := atan2(-dir.x, -dir.z)
			stalker_node.rotation.y = lerp_angle(stalker_node.rotation.y, want_yaw, clampf(delta * 9.0, 0.0, 1.0))

			_step_accum += cur_spd * delta
			var step_len := 1.45 if state == STATE_CHASE else 1.75
			if _step_accum >= step_len:
				_step_accum = 0.0
				SynthAudio.play_3d("monster_step", stalker_node.global_position, 0.5 if state == STATE_CHASE else -3.5, randf_range(0.92, 1.06))
				_apply_step_tremor()

	_play_anim(cur_anim)
	_broadcast_stalker_net(delta, cur_anim)


func _check_echolocation_detection() -> void:
	if local_player == null or local_player.is_dead or local_player.is_downed or local_player.is_caged:
		return
	var d := stalker_node.global_position.distance_to(local_player.global_position)
	if d > 14.0 * hearing_multiplier:
		return
	var speed_2d := Vector2(local_player.velocity.x, local_player.velocity.z).length()
	var moving_loudly := speed_2d > 0.55 and not local_player.is_crouching
	var breathing_close := d < 6.8 and not local_player.is_holding_breath
	if moving_loudly or breathing_close:
		if local_player.is_hiding_in_locker and not local_player.current_locker_id.is_empty():
			begin_locker_inspection(local_player.current_locker_id)
		else:
			_evaluate_hearing(local_player.global_position, 22.0)


func _find_nearby_occupied_locker(max_dist: float) -> String:
	for lid in lockers_ref.keys():
		var lk: Dictionary = lockers_ref[lid]
		if bool(lk.get("occupied", false)):
			var p: Vector3 = lk["exit_pos"]
			if stalker_node.global_position.distance_to(p) <= max_dist:
				return str(lid)
	return ""


func _check_client_proximity_sfx(delta: float) -> void:
	_step_accum += delta
	if _step_accum >= 0.65 and not (state in [STATE_COOLDOWN, STATE_STUNNED, STATE_ECHOLOCATE]):
		_step_accum = 0.0
		SynthAudio.play_3d("monster_step", stalker_node.global_position, -4.0)
		_apply_step_tremor()


func _broadcast_stalker_net(delta: float, anim_key: String) -> void:
	if NetRelay.room_code.is_empty() or not NetRelay.is_host or stalker_node == null:
		return
	_net_sync_timer += delta
	if _net_sync_timer >= 0.08:
		_net_sync_timer = 0.0
		var p := stalker_node.global_position
		NetRelay.send_game_event("stalker_sync", {
			"pos": [snappedf(p.x, 0.02), snappedf(p.y, 0.02), snappedf(p.z, 0.02)],
			"yaw": snappedf(stalker_node.rotation.y, 0.02),
			"state": state,
			"anim": anim_key
		})


func _sense_any_survivor() -> Dictionary:
	var best: Dictionary = {}
	var best_d := 999.0

	if local_player != null and not local_player.is_dead and not local_player.is_downed and not local_player.is_caged:
		if _can_detect_local_player():
			best_d = stalker_node.global_position.distance_to(local_player.global_position)
			best = {"is_local": true, "pos": local_player.global_position, "peer_id": ""}

	for pid in remote_players.keys():
		var rp: RemoteListener = remote_players[pid]
		if is_instance_valid(rp) and not rp.is_downed and not rp.is_caged and not rp.is_frozen and not rp.is_hiding:
			var d := stalker_node.global_position.distance_to(rp.global_position)
			var detect_r := 9.5 if rp.flashlight_on else (2.4 if rp.is_crouching else 4.5)
			if d <= detect_r and _has_line_of_sight(rp.global_position + Vector3(0, 1.1, 0)) and d < best_d:
				best_d = d
				best = {"is_local": false, "pos": rp.global_position, "peer_id": pid}
	return best


func _can_detect_local_player() -> bool:
	if local_player.is_hiding_in_locker:
		return not _saw_player_enter_locker_id.is_empty()
	if local_player.is_under_desk and local_player.is_crouching and state != STATE_CHASE:
		return false

	var p_pos := local_player.global_position
	var d := stalker_node.global_position.distance_to(p_pos)
	if not _has_line_of_sight(local_player.head.global_position):
		return false

	var fwd := -stalker_node.global_transform.basis.z
	var to_p := (p_pos - stalker_node.global_position).normalized()
	var in_front := fwd.dot(to_p) > 0.20

	if d <= 2.1 and not (local_player.is_under_desk and local_player.is_crouching) and not local_player.is_holding_breath:
		return true
	if d <= 1.25 and not (local_player.is_under_desk and local_player.is_crouching):
		return true
	if local_player.flashlight_on and in_front and d <= 10.0:
		return true
	if not local_player.is_crouching and in_front and d <= 5.8:
		return true
	return false


func _has_line_of_sight(target_eye: Vector3) -> bool:
	if stalker_node == null:
		return false
	var space := get_world_3d().direct_space_state
	var from := stalker_node.global_position + Vector3(0, 1.65, 0)
	var q := PhysicsRayQueryParameters3D.create(from, target_eye)
	if local_player != null:
		q.exclude = [local_player.get_rid()]
	var hit := space.intersect_ray(q)
	return hit.is_empty()


func _auto_open_or_smash_doors() -> void:
	for d in doors_ref:
		if not bool(d["is_open"]):
			var dp: Vector3 = d["world_pos"]
			var reach := 2.15 if state == STATE_CHASE else 1.85
			if stalker_node.global_position.distance_to(dp) <= reach:
				d["is_open"] = true
				if state == STATE_CHASE:
					# Frenzy Door Smash!
					d["target_angle"] = -1.68
					d["angle"] = -1.25
					SynthAudio.play_3d("door_smash", dp + Vector3(0, 1.2, 0), 3.0, randf_range(0.92, 1.05))
					door_smashed_nearby.emit(dp)
				else:
					d["target_angle"] = -1.52
					SynthAudio.play_3d("door_creak", dp + Vector3(0, 1.2, 0), -2.0, 0.85)


func _pick_next_patrol_target() -> void:
	if nav_nodes.is_empty():
		return
	_patrol_leg_counter += 1
	var idx := randi() % nav_nodes.size()

	# Director Tether: every 2nd patrol leg, pick a room in the general wing of an active player (12m..32m away)
	if (_patrol_leg_counter % 2 == 0) and local_player != null and not local_player.is_dead and not local_player.is_caged:
		var candidates: Array[int] = []
		for i in range(nav_nodes.size()):
			var dp := nav_nodes[i].distance_to(local_player.global_position)
			if dp >= 12.0 and dp <= 32.0 and i != _last_patrol_idx:
				candidates.append(i)
		if not candidates.is_empty():
			idx = candidates[randi() % candidates.size()]

	if nav_nodes.size() > 1 and idx == _last_patrol_idx:
		idx = (idx + 1) % nav_nodes.size()
	_last_patrol_idx = idx
	_build_nav_path_to(nav_nodes[idx])

	if _patrol_leg_counter > 1 and stalker_node != null and state == STATE_PATROL and get_distance_to_local_player() <= 22.0:
		if randf() < 0.70:
			var clip := "echolocate_click" if randf() < 0.45 else "monster_snarl"
			var vol := -9.0 if clip == "echolocate_click" else -7.0
			var pitch := randf_range(0.76, 0.90)
			SynthAudio.play_3d(clip, stalker_node.global_position + Vector3(0, 1.8, 0), vol, pitch)


func _nearest_nav_idx(pos: Vector3) -> int:
	var space := get_world_3d().direct_space_state
	var from := Vector3(pos.x, 1.45, pos.z)
	var best_i := 0
	var best_score := 999999.0
	for i in range(nav_nodes.size()):
		var d := pos.distance_to(nav_nodes[i])
		var score := d
		if d > 0.5 and d < 18.0:
			var q := PhysicsRayQueryParameters3D.create(from, Vector3(nav_nodes[i].x, 1.45, nav_nodes[i].z))
			if local_player != null:
				q.exclude = [local_player.get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var col := hit.get("collider") as Node
				if col == null or str(col.get_meta("interact_type", "")) != "door":
					score += 25.0
		if score < best_score:
			best_score = score
			best_i = i
	return best_i


func _build_nav_path_to(dest: Vector3) -> void:
	_current_path.clear()
	if nav_nodes.is_empty():
		_current_path.append(dest)
		return
	var start_i := _nearest_nav_idx(stalker_node.global_position)
	var goal_i := _nearest_nav_idx(dest)
	if start_i == goal_i:
		_current_path.append(dest)
		return

	var n := nav_nodes.size()
	var dist: Array[float] = []
	var prev: Array[int] = []
	var visited: Array[bool] = []
	for _i in range(n):
		dist.append(999999.0)
		prev.append(-1)
		visited.append(false)
	dist[start_i] = 0.0

	for _step in range(n):
		var u := -1
		var best := 999999.0
		for i in range(n):
			if not visited[i] and dist[i] < best:
				best = dist[i]
				u = i
		if u == -1 or u == goal_i:
			break
		visited[u] = true
		for v_var in nav_adj[u]:
			var v := int(v_var)
			var alt := dist[u] + nav_nodes[u].distance_to(nav_nodes[v])
			if alt < dist[v]:
				dist[v] = alt
				prev[v] = u

	var rev: Array[Vector3] = []
	var cur := goal_i
	while cur != -1:
		rev.append(nav_nodes[cur])
		cur = prev[cur]
	rev.reverse()
	for pt in rev:
		_current_path.append(pt)
	_current_path.append(dest)


func _play_anim(key: String) -> void:
	if anim_player == null:
		return
	var real_name: String = _anim_map.get(key, "")
	if real_name.is_empty():
		return
	if anim_player.current_animation != real_name:
		anim_player.play(real_name, 0.18)
