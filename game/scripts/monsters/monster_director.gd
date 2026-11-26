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

const GRID_MIN_X := -32.0
const GRID_MAX_X := 32.0
const GRID_MIN_Z := -28.0
const GRID_MAX_Z := 28.0
const GRID_CELL := 0.80
const GRID_W := 80
const GRID_H := 70

var active: bool = false
var state: String = STATE_PATROL
var stalker_node: Node3D = null
var stalker_body: CharacterBody3D = null
var anim_player: AnimationPlayer = null

var nav_nodes: Array[Vector3] = []
var nav_adj: Array = []
var doors_ref: Array[Dictionary] = []
var lockers_ref: Dictionary = {}

var local_player: ListenerPlayer = null
var remote_players: Dictionary = {}

var patrol_speed: float = 2.15
var investigate_speed: float = 3.40
var chase_speed: float = 4.55
var hearing_multiplier: float = 1.0

var _aura_light: OmniLight3D = null
var _jumpscare_face_light: OmniLight3D = null
var _jumpscare_active: bool = false
var _jumpscare_skel: Skeleton3D = null
var _jumpscare_head_bone: int = -1
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
var _stuck_timer: float = 0.0
var _stuck_anchor_pos: Vector3 = Vector3.ZERO
var _stuck_rebuilds: int = 0
var _repath_cd: float = 0.0
var _last_planned_goal: Vector3 = Vector3.ZERO
var _progress_timer: float = 0.0
var _progress_anchor: Vector3 = Vector3.ZERO
var _wall_slide_timer: float = 0.0
var _wall_slide_dir: Vector3 = Vector3.ZERO
var _ambient_vocal_timer: float = 7.0
var _listen_pause_timer: float = 0.0
var _listen_pause_phase: float = 0.0
var _listen_pause_yaw_base: float = 0.0
var _door_flicker_timer: float = 0.0
var _door_snarl_cooldown: float = 0.0

var _grid_baked: bool = false
var _grid_walkable: PackedByteArray = PackedByteArray()
var _grid_near_blocked: PackedByteArray = PackedByteArray()
var _door_ex_rids: Array[RID] = []

var _alert_snap_timer: float = 0.0
var _alert_snap_yaw: float = 0.0
var _alert_flare_timer: float = 0.0
var _suspicion: float = 0.0
var _suspicion_anchor: Vector3 = Vector3.ZERO
var _search_points: Array[Vector3] = []
var _search_points_generated: bool = false
var _search_pause_timer: float = 0.0

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
	_jumpscare_skel = null
	_jumpscare_head_bone = -1
	if _jumpscare_face_light != null and is_instance_valid(_jumpscare_face_light):
		_jumpscare_face_light.queue_free()
	_jumpscare_face_light = null
	if stalker_node != null and is_instance_valid(stalker_node):
		stalker_node.queue_free()
	stalker_node = null
	stalker_body = null
	anim_player = null
	_aura_light = null
	_current_path.clear()
	_saw_player_enter_locker_id = ""
	_inspect_locker_id = ""
	_post_chase_sweeps_left = 0
	_last_sweep_idx = -1
	_stuck_timer = 0.0
	_stuck_anchor_pos = Vector3.ZERO
	_stuck_rebuilds = 0
	_repath_cd = 0.0
	_last_planned_goal = Vector3.ZERO
	_progress_timer = 0.0
	_progress_anchor = Vector3.ZERO
	_wall_slide_timer = 0.0
	_wall_slide_dir = Vector3.ZERO
	_ambient_vocal_timer = 7.0
	_listen_pause_timer = 0.0
	_listen_pause_phase = 0.0
	_door_flicker_timer = 0.0
	_door_snarl_cooldown = 0.0
	_grid_baked = false
	_grid_walkable.clear()
	_grid_near_blocked.clear()
	_door_ex_rids.clear()
	_alert_snap_timer = 0.0
	_alert_snap_yaw = 0.0
	_alert_flare_timer = 0.0
	_suspicion = 0.0
	_suspicion_anchor = Vector3.ZERO
	_search_points.clear()
	_search_points_generated = false
	_search_pause_timer = 0.0
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
		patrol_speed = 2.55
		investigate_speed = 3.90
		chase_speed = 5.05
		hearing_multiplier = 1.35
	else:
		patrol_speed = 2.15
		investigate_speed = 3.40
		chase_speed = 4.55
		hearing_multiplier = 1.0

	stalker_body = CharacterBody3D.new()
	stalker_body.name = "Listener07Body"
	stalker_body.collision_layer = 4
	stalker_body.collision_mask = 1
	stalker_body.floor_max_angle = 0.6
	stalker_body.position = spawn_pos

	var col_shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.95
	col_shape.shape = cap
	col_shape.position = Vector3(0.0, 0.98, 0.0)
	stalker_body.add_child(col_shape)

	var model := AssetLibrary.instantiate_model("monster_stalker")
	stalker_body.add_child(model)
	stalker_node = stalker_body
	add_child(stalker_node)

	var aura := OmniLight3D.new()
	aura.position = Vector3(0, 1.95, -0.25)
	aura.light_color = Color(0.85, 0.12, 0.10)
	aura.light_energy = 0.35
	aura.omni_range = 3.4
	stalker_node.add_child(aura)
	_aura_light = aura
	_aura_phase = 0.0

	anim_player = AssetLibrary.find_animation_player(model)
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
	_stuck_timer = 0.0
	_stuck_anchor_pos = spawn_pos
	_stuck_rebuilds = 0
	_progress_timer = 0.0
	_progress_anchor = spawn_pos
	_wall_slide_timer = 0.0
	_repath_cd = 0.0
	_ambient_vocal_timer = randf_range(5.5, 10.5)
	_listen_pause_timer = 0.0
	_pick_next_patrol_target()


func reset_after_catch(retreat_pos: Vector3) -> void:
	if not active or stalker_node == null:
		return
	end_jumpscare_pose()
	stalker_node.global_position = retreat_pos
	if stalker_body != null:
		stalker_body.velocity = Vector3.ZERO
	_saw_player_enter_locker_id = ""
	_inspect_locker_id = ""
	_post_chase_sweeps_left = 0
	_last_sweep_idx = -1
	_listen_pause_timer = 0.0
	_alert_snap_timer = 0.0
	_alert_flare_timer = 0.0
	_suspicion = 0.0
	_suspicion_anchor = Vector3.ZERO
	_search_points.clear()
	_search_points_generated = false
	_search_pause_timer = 0.0
	_stuck_timer = 0.0
	_stuck_anchor_pos = retreat_pos
	_stuck_rebuilds = 0
	_repath_cd = 0.0
	_last_planned_goal = Vector3.ZERO
	_progress_timer = 0.0
	_progress_anchor = retreat_pos
	_wall_slide_timer = 0.0
	_wall_slide_dir = Vector3.ZERO
	state = STATE_COOLDOWN
	_state_timer = 4.2
	_current_path.clear()
	_play_anim("idle")
	stalker_state_changed.emit(state)


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for ch in n.get_children():
		var res := _find_skeleton(ch)
		if res != null:
			return res
	return null


func get_jumpscare_head_world_pos() -> Vector3:
	if stalker_node == null or not is_instance_valid(stalker_node):
		return Vector3.ZERO
	if _jumpscare_skel != null and is_instance_valid(_jumpscare_skel) and _jumpscare_head_bone >= 0:
		return _jumpscare_skel.global_transform * _jumpscare_skel.get_bone_global_pose(_jumpscare_head_bone).origin
	return stalker_node.global_position + Vector3(0.0, 1.72, 0.0)


func trigger_jumpscare_pose(cam: Camera3D) -> void:
	if stalker_node == null or not is_instance_valid(stalker_node) or cam == null or not is_instance_valid(cam):
		return
	_jumpscare_active = true
	state = STATE_COOLDOWN
	_state_timer = 3.5
	_current_path.clear()
	_saw_player_enter_locker_id = ""
	_inspect_locker_id = ""

	var eye_pos := cam.global_position
	var approach_dir := Vector3(
		stalker_node.global_position.x - eye_pos.x,
		0.0,
		stalker_node.global_position.z - eye_pos.z
	)
	if approach_dir.length_squared() < 0.0001:
		var cam_fwd := -cam.global_transform.basis.z
		approach_dir = Vector3(cam_fwd.x, 0.0, cam_fwd.z)
	if approach_dir.length_squared() < 0.0001:
		approach_dir = Vector3(0.0, 0.0, -1.0)
	else:
		approach_dir = approach_dir.normalized()

	var ex: Array[RID] = []
	if stalker_body != null:
		ex.append(stalker_body.get_rid())
	if local_player != null:
		ex.append(local_player.get_rid())

	var best_dir := approach_dir
	var best_dist := 1.45
	var space := get_world_3d().direct_space_state if is_inside_tree() and get_world_3d() != null else null
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(eye_pos, eye_pos + approach_dir * 1.45)
		q.collision_mask = 1
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			best_dist = eye_pos.distance_to(hit["position"] as Vector3)
			var angles: Array[float] = [0.0, 0.785398, -0.785398, 1.570796, -1.570796, 2.356194, -2.356194, PI]
			for ang in angles:
				var cand := approach_dir.rotated(Vector3.UP, ang).normalized()
				var cq := PhysicsRayQueryParameters3D.create(eye_pos, eye_pos + cand * 1.45)
				cq.collision_mask = 1
				cq.exclude = ex
				var chit := space.intersect_ray(cq)
				var cdist := 1.45 if chit.is_empty() else eye_pos.distance_to(chit["position"] as Vector3)
				if cdist > best_dist + 0.02:
					best_dist = cdist
					best_dir = cand
					if best_dist >= 1.44:
						break

	if local_player != null and is_instance_valid(local_player):
		local_player.rotation.y = atan2(-best_dir.x, -best_dir.z)
		local_player._cam_trauma = 0.0
		local_player._cam_roll = 0.0
		if local_player.head != null:
			local_player.head.rotation.x = 0.0
		if local_player.camera != null:
			local_player.camera.rotation = Vector3.ZERO
			local_player.camera.position = Vector3.ZERO
			local_player.camera.h_offset = 0.0
			local_player.camera.v_offset = 0.0
		local_player.force_update_transform()
		if local_player.head != null:
			local_player.head.force_update_transform()
		if local_player.camera != null:
			local_player.camera.force_update_transform()

	var cam_pos := cam.global_position
	var place_dist := clampf(best_dist - 0.28, 0.96, 1.12)
	var target_pos := cam_pos + best_dir * place_dist
	target_pos.y = cam_pos.y - 1.72
	stalker_node.global_position = target_pos

	var to_cam := Vector3(cam_pos.x - target_pos.x, 0.0, cam_pos.z - target_pos.z)
	if to_cam.length_squared() > 0.0001:
		stalker_node.rotation.y = atan2(-to_cam.x, -to_cam.z)
	stalker_node.force_update_transform()

	if anim_player != null and is_instance_valid(anim_player):
		anim_player.speed_scale = 1.6
		var atk_name: String = _anim_map.get("attack", "")
		if not atk_name.is_empty():
			anim_player.stop()
			anim_player.play(atk_name, 0.0)
			anim_player.seek(0.0, true)
			anim_player.advance(0.0)

	_jumpscare_skel = _find_skeleton(stalker_node)
	_jumpscare_head_bone = -1
	if _jumpscare_skel != null:
		_jumpscare_head_bone = _jumpscare_skel.find_bone("Head")
		if _jumpscare_head_bone < 0:
			_jumpscare_head_bone = _jumpscare_skel.find_bone("Neck")
		if _jumpscare_head_bone >= 0:
			var head_world := _jumpscare_skel.global_transform * _jumpscare_skel.get_bone_global_pose(_jumpscare_head_bone).origin
			stalker_node.global_position.y += (cam_pos.y - 0.04) - head_world.y
			stalker_node.force_update_transform()

	if _jumpscare_face_light != null and is_instance_valid(_jumpscare_face_light):
		_jumpscare_face_light.queue_free()
	var face_local := stalker_node.to_local(get_jumpscare_head_world_pos())
	var face_light := OmniLight3D.new()
	face_light.position = face_local + Vector3(0.18, 0.16, -0.46)
	face_light.light_color = Color(1.0, 0.30, 0.14)
	face_light.light_energy = 2.9
	face_light.omni_range = 3.0
	stalker_node.add_child(face_light)
	_jumpscare_face_light = face_light


func end_jumpscare_pose() -> void:
	_jumpscare_active = false
	_jumpscare_skel = null
	_jumpscare_head_bone = -1
	if _jumpscare_face_light != null and is_instance_valid(_jumpscare_face_light):
		_jumpscare_face_light.queue_free()
	_jumpscare_face_light = null
	if stalker_node != null and is_instance_valid(stalker_node):
		stalker_node.global_position.y = 0.0
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
		_alert_snap_timer = 0.0
		_alert_flare_timer = 0.0
		_suspicion = 0.0
		_search_points.clear()
		_search_points_generated = false
		_search_pause_timer = 0.0
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
	_alert_snap_timer = 0.0
	_search_points.clear()
	_search_points_generated = false
	_search_pause_timer = 0.0
	state = STATE_INSPECT_LOCKER
	var lk: Dictionary = lockers_ref[locker_id]
	var stand_pos: Vector3 = lk["exit_pos"]
	_build_nav_path_to(Vector3(stand_pos.x, 0.0, stand_pos.z))
	SynthAudio.play_3d("monster_snarl", stalker_node.global_position + Vector3(0, 1.8, 0), -1.0, 0.88)
	stalker_state_changed.emit(state)


func on_network_noise(world_pos: Vector3, radius: float, source_tag: String = "") -> void:
	if not active or not NetRelay.is_host:
		return
	_evaluate_hearing(world_pos, radius, source_tag)


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
	q.collision_mask = 1 | 16
	var ex: Array[RID] = []
	if stalker_body != null:
		ex.append(stalker_body.get_rid())
	if local_player != null:
		ex.append(local_player.get_rid())
	for d in doors_ref:
		if bool(d.get("is_open", false)):
			var col := d.get("collider") as CollisionObject3D
			if col != null and is_instance_valid(col):
				ex.append(col.get_rid())
	q.exclude = ex
	var hit := space.intersect_ray(q)
	return hit.is_empty()


func has_recent_echolocation_ping() -> bool:
	return (Time.get_ticks_msec() * 0.001 - _last_echo_time_sec) < 1.8


func _on_local_noise(world_pos: Vector3, radius: float, source_tag: String) -> void:
	if not NetRelay.room_code.is_empty() and not NetRelay.is_host:
		NetRelay.send_game_event("noise", {
			"pos": [snappedf(world_pos.x, 0.05), snappedf(world_pos.y, 0.05), snappedf(world_pos.z, 0.05)],
			"r": snappedf(radius, 0.1),
			"tag": source_tag
		})
		return
	_evaluate_hearing(world_pos, radius, source_tag)


func _evaluate_hearing(world_pos: Vector3, radius: float, source_tag: String = "") -> void:
	if not active or stalker_node == null or state in [STATE_COOLDOWN, STATE_STUNNED]:
		return
	var dist := stalker_node.global_position.distance_to(world_pos)
	if dist > radius * hearing_multiplier:
		return

	var is_distraction := (source_tag == "bottle_shatter" or source_tag == "pa_siren")
	var goal := Vector3(world_pos.x, 0.0, world_pos.z)

	if state == STATE_CHASE:
		if is_distraction and _sense_any_survivor().is_empty():
			# Lured away from a blind search by a thrown bottle or PA siren!
			_saw_player_enter_locker_id = ""
		else:
			_stuck_timer = 0.0
			_stuck_rebuilds = 0
			_stuck_anchor_pos = stalker_node.global_position
			_goal_pos = goal
			_build_nav_path_to(_goal_pos)
			return

	_listen_pause_timer = 0.0
	_stuck_timer = 0.0
	_stuck_rebuilds = 0
	_stuck_anchor_pos = stalker_node.global_position

	var susp_bump := 0.35 if radius < 12.0 else 0.55
	if is_distraction:
		susp_bump = 0.65
		_inspect_locker_id = ""
		_saw_player_enter_locker_id = ""
	if _suspicion_anchor == Vector3.ZERO or world_pos.distance_to(_suspicion_anchor) > 16.0:
		_suspicion = susp_bump
	else:
		_suspicion = clampf(_suspicion + susp_bump, 0.0, 1.0)
	_suspicion_anchor = world_pos

	_search_points.clear()
	_search_points_generated = false
	_search_pause_timer = 0.0
	_post_chase_sweeps_left = 0
	_last_sweep_idx = -1

	_goal_pos = goal
	_build_nav_path_to(_goal_pos)

	var prev := state
	state = STATE_INVESTIGATE
	_state_timer = lerpf(4.8, 6.8, _suspicion)

	var to_sound := Vector3(world_pos.x - stalker_node.global_position.x, 0.0, world_pos.z - stalker_node.global_position.z)
	if prev in [STATE_PATROL, STATE_ECHOLOCATE] or (is_distraction and prev != STATE_INVESTIGATE):
		_alert_snap_timer = 0.55
		if to_sound.length_squared() > 0.0001:
			_alert_snap_yaw = atan2(-to_sound.x, -to_sound.z)
			stalker_node.rotation.y = _alert_snap_yaw
		_alert_flare_timer = 0.75
		SynthAudio.play_3d("monster_chatter", stalker_node.global_position + Vector3(0, 1.82, 0), 1.0, randf_range(0.94, 1.08))
		stalker_state_changed.emit(state)
	elif is_distraction:
		_alert_snap_timer = 0.35
		if to_sound.length_squared() > 0.0001:
			_alert_snap_yaw = atan2(-to_sound.x, -to_sound.z)
			stalker_node.rotation.y = _alert_snap_yaw
		_alert_flare_timer = 0.65
		SynthAudio.play_3d("monster_chatter", stalker_node.global_position + Vector3(0, 1.82, 0), 0.5, randf_range(0.96, 1.10))


func _update_aura_light(delta: float) -> void:
	_door_flicker_timer = maxf(0.0, _door_flicker_timer - delta)
	_door_snarl_cooldown = maxf(0.0, _door_snarl_cooldown - delta)
	_alert_flare_timer = maxf(0.0, _alert_flare_timer - delta)
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
			target_col = Color(1.0, 0.06, 0.06)
			target_range = 4.8
			target_energy = 1.25 if rm else (1.22 + 0.44 * sin(_aura_phase * 23.0) * cos(_aura_phase * 11.0))
		STATE_STUNNED:
			target_col = Color(0.62, 0.25, 0.20)
			target_range = 2.4
			target_energy = 0.12 if rm else (0.08 + 0.10 * maxf(0.0, sin(_aura_phase * 29.0)))
		STATE_COOLDOWN:
			target_col = Color(0.70, 0.10, 0.10)
			target_range = 2.8
			target_energy = 0.22

	if (_door_flicker_timer > 0.0 or _alert_flare_timer > 0.0) and state != STATE_STUNNED:
		target_col = Color(1.0, 0.08, 0.06)
		target_range = maxf(target_range, 4.6)
		target_energy = maxf(target_energy, 1.25) if rm else (maxf(target_energy, 1.05) + 0.55 * absf(sin(_aura_phase * 27.0)))

	var alpha := 1.0 - exp(-delta * 10.0)
	_aura_light.light_color = _aura_light.light_color.lerp(target_col, alpha)
	_aura_light.light_energy = lerpf(_aura_light.light_energy, target_energy, alpha)
	_aura_light.omni_range = lerpf(_aura_light.omni_range, target_range, alpha)


func _update_ambient_vocals(delta: float) -> void:
	if state in [STATE_STUNNED, STATE_COOLDOWN] or stalker_node == null:
		return
	_ambient_vocal_timer -= delta
	if _ambient_vocal_timer <= 0.0:
		_ambient_vocal_timer = randf_range(5.5, 10.5)
		var clip := "monster_click_idle" if randf() < 0.5 else "monster_breath_rasp"
		var vol := -1.5 if clip == "monster_click_idle" else -1.0
		SynthAudio.play_3d(clip, stalker_node.global_position + Vector3(0, 1.82, 0), vol, randf_range(0.90, 1.12))


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

	_repath_cd = maxf(0.0, _repath_cd - delta)
	_wall_slide_timer = maxf(0.0, _wall_slide_timer - delta)
	_update_ambient_vocals(delta)

	if not NetRelay.room_code.is_empty() and not NetRelay.is_host:
		_check_client_proximity_sfx(delta)
		return

	if not _grid_baked:
		_bake_walkability_grid()
		if _grid_baked and _goal_pos != Vector3.ZERO and not (state in [STATE_STUNNED, STATE_COOLDOWN, STATE_ECHOLOCATE]):
			_build_nav_path_to(_goal_pos)

	if state != STATE_CHASE and _suspicion > 0.0:
		_suspicion = maxf(0.0, _suspicion - 0.06 * delta)

	_auto_open_or_smash_doors(delta)

	# 1. STUNNED by Sonic Strobe Flare
	if state == STATE_STUNNED:
		if stalker_body != null:
			stalker_body.velocity = Vector3.ZERO
		_stuck_timer = 0.0
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
		if stalker_body != null:
			stalker_body.velocity = Vector3.ZERO
		_stuck_timer = 0.0
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
		if stalker_body != null:
			stalker_body.velocity = Vector3.ZERO
		_stuck_timer = 0.0
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
	if state == STATE_PATROL and _listen_pause_timer <= 0.0:
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
		_listen_pause_timer = 0.0
		_alert_snap_timer = 0.0
		_search_points.clear()
		_search_pause_timer = 0.0
		if state != STATE_CHASE:
			state = STATE_CHASE
			_repath_cd = 0.0
			_progress_timer = 0.0
			_progress_anchor = stalker_node.global_position
			_wall_slide_timer = 0.0
			_door_flicker_timer = 0.95
			SynthAudio.play_3d("monster_roar", stalker_node.global_position + Vector3(0, 1.8, 0), 2.0)
			stalker_state_changed.emit(state)
		_state_timer = 5.0
		if _has_line_of_sight(tpos + Vector3(0, 1.0, 0)) and _has_clear_body_path(_goal_pos):
			_current_path = [_goal_pos]
			_last_planned_goal = _goal_pos
		else:
			if _repath_cd <= 0.0 or _current_path.is_empty() or _last_planned_goal.distance_to(_goal_pos) > 0.75:
				_repath_cd = 0.14
				_last_planned_goal = _goal_pos
				_build_nav_path_to(_goal_pos)

		if stalker_node.global_position.distance_to(_goal_pos) <= 1.42:
			if stalker_body != null:
				stalker_body.velocity = Vector3.ZERO
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
			if _listen_pause_timer > 0.0:
				_listen_pause_timer -= delta
				_listen_pause_phase += delta
				cur_anim = "idle"
				stalker_node.rotation.y = _listen_pause_yaw_base + sin(_listen_pause_phase * (TAU / 1.6)) * 0.55
				if _listen_pause_timer <= 0.0:
					_pick_next_patrol_target()
					cur_anim = "walk"
			elif _current_path.is_empty():
				if _patrol_leg_counter > 0 and randf() < 0.25:
					_listen_pause_timer = 1.6
					_listen_pause_phase = 0.0
					_listen_pause_yaw_base = stalker_node.rotation.y
					cur_anim = "idle"
					SynthAudio.play_3d("monster_click_idle", stalker_node.global_position + Vector3(0, 1.85, 0), -4.0, randf_range(0.88, 1.06))
				else:
					_pick_next_patrol_target()

		STATE_INVESTIGATE:
			if _alert_snap_timer > 0.0:
				_alert_snap_timer -= delta
				if stalker_body != null:
					stalker_body.velocity = Vector3.ZERO
				stalker_node.rotation.y = lerp_angle(stalker_node.rotation.y, _alert_snap_yaw, clampf(delta * 26.0, 0.0, 1.0))
				_play_anim("idle")
				_broadcast_stalker_net(delta, "idle")
				return
			cur_spd = lerpf(investigate_speed, lerpf(investigate_speed, chase_speed, 0.55), _suspicion)
			cur_anim = "walk"
			if _current_path.is_empty():
				var susp_lid := _find_nearby_occupied_locker(6.2)
				if not susp_lid.is_empty():
					begin_locker_inspection(susp_lid)
					return
				if _search_pause_timer > 0.0:
					_search_pause_timer -= delta
					cur_anim = "idle"
					stalker_node.rotation.y += sin(_state_timer * 3.1) * delta * 1.5
					if _search_pause_timer <= 0.0 and not _search_points.is_empty():
						var next_sp: Vector3 = _search_points[0]
						_search_points.remove_at(0)
						_goal_pos = next_sp
						_build_nav_path_to(next_sp)
						cur_anim = "walk"
				elif not _search_points_generated and _suspicion >= 0.35 and _post_chase_sweeps_left <= 0:
					_search_points_generated = true
					_search_points = _generate_search_points(_goal_pos, 3 if _suspicion >= 0.72 else 2)
					if not _search_points.is_empty():
						_search_pause_timer = 0.80
						cur_anim = "idle"
						var sniff_clip := "monster_click_idle" if randf() < 0.5 else "monster_breath_rasp"
						SynthAudio.play_3d(sniff_clip, stalker_node.global_position + Vector3(0, 1.82, 0), -2.5, randf_range(0.90, 1.08))
				elif not _search_points.is_empty():
					_search_pause_timer = 0.80
					cur_anim = "idle"
					var sniff_clip2 := "monster_click_idle" if randf() < 0.5 else "monster_breath_rasp"
					SynthAudio.play_3d(sniff_clip2, stalker_node.global_position + Vector3(0, 1.82, 0), -2.5, randf_range(0.90, 1.08))
				else:
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
			elif _post_chase_sweeps_left > 0 or _suspicion >= 0.55:
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

	while not _current_path.is_empty():
		var head_wp: Vector3 = _current_path[0]
		var dist_2d := Vector2(head_wp.x - stalker_node.global_position.x, head_wp.z - stalker_node.global_position.z).length()
		if dist_2d < 0.45:
			_current_path.pop_front()
		else:
			break

	if not _current_path.is_empty() and cur_anim != "idle" and stalker_body != null:
		var wp: Vector3 = _current_path[0]
		var to_wp := Vector3(wp.x - stalker_node.global_position.x, 0.0, wp.z - stalker_node.global_position.z)
		var d := to_wp.length()
		var dir := to_wp / maxf(d, 0.0001)

		var is_pursuit := (state == STATE_CHASE or state == STATE_INVESTIGATE)
		var funnel := _find_doorway_funnel_bias(dir, wp) if is_pursuit else {"has_door": false, "dir": dir, "door_center": wp}
		var has_funnel_door := bool(funnel["has_door"])
		var funnel_dir: Vector3 = funnel["dir"]
		var funnel_door_center: Vector3 = funnel["door_center"]
		if has_funnel_door:
			dir = dir.lerp(funnel_dir, 0.78).normalized()

		var steered_dir := _steer_with_whiskers(dir)
		if is_pursuit and _wall_slide_timer > 0.0:
			steered_dir = _wall_slide_dir.lerp(funnel_dir, 0.45).normalized() if has_funnel_door else _wall_slide_dir

		var step_spd := minf(cur_spd, d / maxf(delta, 0.001))
		var vel_y := -0.1 if stalker_body.is_on_floor() else -6.0
		stalker_body.velocity = Vector3(steered_dir.x * step_spd, vel_y, steered_dir.z * step_spd)
		stalker_body.move_and_slide()
		if stalker_body.global_position.y < -0.05 or stalker_body.global_position.y > 0.25:
			stalker_body.global_position.y = 0.0

		if is_pursuit:
			_progress_timer += delta
			var real_vel := stalker_body.get_real_velocity()
			var real_spd := Vector2(real_vel.x, real_vel.z).length()
			var need_slide := false
			if _progress_timer >= 0.22:
				var prog_2d := Vector2(
					stalker_node.global_position.x - _progress_anchor.x,
					stalker_node.global_position.z - _progress_anchor.z
				).length()
				_progress_timer = 0.0
				_progress_anchor = stalker_node.global_position
				if stalker_body.is_on_wall() and prog_2d < 0.14:
					need_slide = true
			elif stalker_body.is_on_wall() and real_spd < step_spd * 0.25 and _wall_slide_timer <= 0.0:
				need_slide = true

			if need_slide:
				var wn := stalker_body.get_wall_normal()
				wn.y = 0.0
				if wn.length_squared() > 0.0001:
					wn = wn.normalized()
					var tang := wn.cross(Vector3.UP).normalized()
					var aim_pt := funnel_door_center if has_funnel_door else wp
					var to_aim := Vector3(aim_pt.x - stalker_node.global_position.x, 0.0, aim_pt.z - stalker_node.global_position.z)
					if tang.dot(to_aim) < 0.0:
						tang = -tang
					elif absf(tang.dot(to_aim)) < 0.05 and _goal_pos != Vector3.ZERO:
						var to_g := Vector3(_goal_pos.x - stalker_node.global_position.x, 0.0, _goal_pos.z - stalker_node.global_position.z)
						if tang.dot(to_g) < 0.0:
							tang = -tang
					_wall_slide_dir = (tang + wn * 0.12).normalized()
					_wall_slide_timer = 0.24
					_repath_cd = 0.0
		else:
			_progress_timer = 0.0
			_progress_anchor = stalker_node.global_position
			_wall_slide_timer = 0.0

		var want_yaw := atan2(-steered_dir.x, -steered_dir.z)
		stalker_node.rotation.y = lerp_angle(stalker_node.rotation.y, want_yaw, clampf(delta * 9.0, 0.0, 1.0))

		_step_accum += cur_spd * delta
		var step_len := 1.45 if state == STATE_CHASE else 1.75
		if _step_accum >= step_len:
			_step_accum = 0.0
			SynthAudio.play_3d("monster_step", stalker_node.global_position, 0.5 if state == STATE_CHASE else -3.5, randf_range(0.92, 1.06))
			_apply_step_tremor()

		_stuck_timer += delta
		if _stuck_timer >= 0.40:
			var moved_2d := Vector2(stalker_node.global_position.x - _stuck_anchor_pos.x, stalker_node.global_position.z - _stuck_anchor_pos.z).length()
			_stuck_timer = 0.0
			_stuck_anchor_pos = stalker_node.global_position
			if moved_2d < 0.12:
				_handle_stuck_recovery()
			else:
				_stuck_rebuilds = 0
	else:
		if stalker_body != null:
			stalker_body.velocity = Vector3.ZERO
		_stuck_timer = 0.0
		_stuck_anchor_pos = stalker_node.global_position
		_stuck_rebuilds = 0
		_progress_timer = 0.0
		_progress_anchor = stalker_node.global_position
		_wall_slide_timer = 0.0

	_play_anim(cur_anim)
	_broadcast_stalker_net(delta, cur_anim)


func _handle_stuck_recovery() -> void:
	if stalker_node == null:
		return
	_stuck_rebuilds += 1
	if _grid_baked and _goal_pos != Vector3.ZERO and _stuck_rebuilds == 1:
		_build_nav_path_to(_goal_pos)
		return
	if _current_path.size() > 1 and _stuck_rebuilds <= 2:
		_current_path.pop_front()
		return
	if not nav_nodes.is_empty() and _stuck_rebuilds <= 3:
		var cur_i := _nearest_nav_idx(stalker_node.global_position)
		if cur_i >= 0 and cur_i < nav_adj.size():
			var neighbors: Array = nav_adj[cur_i]
			if not neighbors.is_empty():
				var pick_i := int(neighbors[randi() % neighbors.size()])
				_current_path = [nav_nodes[pick_i]]
				if _goal_pos != Vector3.ZERO:
					_current_path.append(_goal_pos)
				return
	if _goal_pos != Vector3.ZERO and _stuck_rebuilds <= 4:
		_build_nav_path_to(_goal_pos)
	else:
		_stuck_rebuilds = 0
		_pick_next_patrol_target()


func _check_echolocation_detection() -> void:
	if local_player == null or local_player.is_dead or local_player.is_downed or local_player.is_caged:
		return
	var d := stalker_node.global_position.distance_to(local_player.global_position)
	if d > 14.0 * hearing_multiplier:
		return
	var speed_2d := Vector2(local_player.velocity.x, local_player.velocity.z).length()
	var moving_loudly := speed_2d > 0.55 and not local_player.is_crouching
	var breathing_close := d < 7.0 and not local_player.is_holding_breath
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
	var speed_2d := Vector2(local_player.velocity.x, local_player.velocity.z).length()
	var is_silent := local_player.is_crouching or speed_2d < 0.35
	var beam_hidden := (not local_player.flashlight_on) or local_player.is_hiding_in_locker or local_player.is_under_desk
	if local_player.is_holding_breath and is_silent and beam_hidden:
		return false

	var d := stalker_node.global_position.distance_to(p_pos)
	if not _has_line_of_sight(local_player.head.global_position):
		return false

	var fwd := -stalker_node.global_transform.basis.z
	var to_p := (p_pos - stalker_node.global_position)
	var in_front := fwd.dot(to_p.normalized()) > 0.20 if to_p.length_squared() > 0.0001 else true

	if not local_player.is_crouching and not local_player.is_holding_breath and d <= 1.45:
		return true
	if d <= 0.55 and not local_player.is_crouching and not local_player.is_under_desk:
		return true
	if local_player.flashlight_on and in_front and d <= 9.5:
		return true
	if not local_player.is_crouching and speed_2d > 0.65 and in_front and d <= 5.2:
		return true
	return false


func _has_line_of_sight(target_eye: Vector3) -> bool:
	if stalker_node == null:
		return false
	var space := get_world_3d().direct_space_state
	var from := stalker_node.global_position + Vector3(0, 1.65, 0)
	var q := PhysicsRayQueryParameters3D.create(from, target_eye)
	q.collision_mask = 1 | 16
	var ex: Array[RID] = []
	if stalker_body != null:
		ex.append(stalker_body.get_rid())
	if local_player != null:
		ex.append(local_player.get_rid())
	for d in doors_ref:
		if bool(d.get("is_open", false)):
			var col := d.get("collider") as CollisionObject3D
			if col != null and is_instance_valid(col):
				ex.append(col.get_rid())
	q.exclude = ex
	var hit := space.intersect_ray(q)
	return hit.is_empty()


func _has_clear_body_path(target_pos: Vector3) -> bool:
	if stalker_node == null:
		return false
	var base := Vector3(stalker_node.global_position.x, 0.0, stalker_node.global_position.z)
	var target_base := Vector3(target_pos.x, 0.0, target_pos.z)
	var to_t := target_base - base
	if to_t.length_squared() < 0.01:
		return true
	var fwd := to_t.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)

	var ex: Array[RID] = []
	if stalker_body != null:
		ex.append(stalker_body.get_rid())
	if local_player != null:
		ex.append(local_player.get_rid())
	for d in doors_ref:
		var col := d.get("collider") as CollisionObject3D
		if col != null and is_instance_valid(col):
			ex.append(col.get_rid())

	var space := get_world_3d().direct_space_state
	var offsets: Array[Vector3] = [
		Vector3(0.0, 0.55, 0.0),
		Vector3(0.0, 1.35, 0.0),
		right * -0.22 + Vector3(0.0, 0.65, 0.0),
		right * 0.22 + Vector3(0.0, 0.65, 0.0),
		right * -0.44 + Vector3(0.0, 0.65, 0.0),
		right * 0.44 + Vector3(0.0, 0.65, 0.0)
	]
	for off in offsets:
		var q := PhysicsRayQueryParameters3D.create(base + off, target_base + off)
		q.collision_mask = 1
		q.exclude = ex
		if not space.intersect_ray(q).is_empty():
			return false
	return true


func _find_doorway_funnel_bias(base_dir: Vector3, wp: Vector3) -> Dictionary:
	var out := {"has_door": false, "dir": base_dir, "door_center": wp}
	if stalker_node == null or doors_ref.is_empty():
		return out
	var pos_2d := Vector3(stalker_node.global_position.x, 0.0, stalker_node.global_position.z)
	var next_pt := _current_path[1] if _current_path.size() > 1 else (_goal_pos if _goal_pos != Vector3.ZERO else wp)
	var wp_2d := Vector3(wp.x, 0.0, wp.z)
	var next_2d := Vector3(next_pt.x, 0.0, next_pt.z)

	var best_dist := 2.45
	var best_door: Dictionary = {}
	for d in doors_ref:
		var dp := Vector3(d["world_pos"].x, 0.0, d["world_pos"].z)
		var dist := pos_2d.distance_to(dp)
		if dist > 2.40:
			continue
		var d_dir: Vector3 = d.get("dir", Vector3(1.0, 0.0, 0.0))
		var d_norm: Vector3 = d.get("normal", Vector3(0.0, 0.0, 1.0))
		var s_pos := (pos_2d - dp).dot(d_norm)
		var s_wp := (wp_2d - dp).dot(d_norm)
		var s_next := (next_2d - dp).dot(d_norm)
		var crosses := (s_pos * s_wp <= 0.20) or (s_pos * s_next <= 0.20)
		if not crosses:
			continue
		var lat_pos := absf((pos_2d - dp).dot(d_dir))
		var lat_wp := absf((wp_2d - dp).dot(d_dir))
		if minf(lat_pos, lat_wp) > 1.75:
			continue
		if dist < best_dist:
			best_dist = dist
			best_door = d

	if best_door.is_empty():
		return out

	var bdp := Vector3(best_door["world_pos"].x, 0.0, best_door["world_pos"].z)
	var bd_dir: Vector3 = best_door.get("dir", Vector3(1.0, 0.0, 0.0))
	var bd_norm: Vector3 = best_door.get("normal", Vector3(0.0, 0.0, 1.0))
	var dir_dot_norm := (next_2d - pos_2d).dot(bd_norm)
	if absf(dir_dot_norm) < 0.05:
		dir_dot_norm = (wp_2d - pos_2d).dot(bd_norm)
	var pass_sign := 1.0 if dir_dot_norm >= 0.0 else -1.0
	var pass_fwd := bd_norm * pass_sign
	var s_toward := (bdp - pos_2d).dot(pass_fwd)
	if s_toward < -0.55:
		return out
	var lat_off := absf((pos_2d - bdp).dot(bd_dir))
	var funnel_pt: Vector3
	if s_toward > 0.14 and s_toward < 0.65 and lat_off > 0.36:
		funnel_pt = bdp - pass_fwd * 0.42
	elif s_toward > 0.18 and lat_off > 0.22:
		funnel_pt = bdp
	else:
		funnel_pt = bdp + pass_fwd * 0.72
	var fdir := funnel_pt - pos_2d
	fdir.y = 0.0
	if fdir.length_squared() < 0.0001:
		return out
	out["has_door"] = true
	out["dir"] = fdir.normalized()
	out["door_center"] = bdp
	return out


func _auto_open_or_smash_doors(_delta: float = 0.0) -> void:
	for d in doors_ref:
		if not bool(d["is_open"]):
			var dp: Vector3 = d["world_pos"]
			var reach := 2.25
			if stalker_node.global_position.distance_to(dp) <= reach:
				d["is_open"] = true
				_door_flicker_timer = 0.95
				if state == STATE_CHASE:
					# Frenzy Door Smash!
					d["target_angle"] = -1.68
					d["angle"] = -1.25
					SynthAudio.play_3d("door_smash", dp + Vector3(0, 1.2, 0), 3.0, randf_range(0.92, 1.05))
					door_smashed_nearby.emit(dp)
				else:
					d["target_angle"] = -1.52
					d["angle"] = minf(float(d.get("angle", 0.0)), -0.55)
					SynthAudio.play_3d("door_creak", dp + Vector3(0, 1.2, 0), -2.0, 0.85)
					if _door_snarl_cooldown <= 0.0:
						SynthAudio.play_3d("monster_snarl", stalker_node.global_position + Vector3(0, 1.8, 0), -1.0, randf_range(0.88, 1.05))
						_door_snarl_cooldown = 1.6


func _pick_next_patrol_target() -> void:
	_suspicion = 0.0
	_suspicion_anchor = Vector3.ZERO
	_search_points.clear()
	_search_points_generated = false
	_search_pause_timer = 0.0
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
	_goal_pos = nav_nodes[idx]
	_build_nav_path_to(_goal_pos)

	if _patrol_leg_counter > 1 and stalker_node != null and state == STATE_PATROL and get_distance_to_local_player() <= 22.0:
		if randf() < 0.70:
			var clip := "echolocate_click" if randf() < 0.45 else "monster_snarl"
			var vol := -9.0 if clip == "echolocate_click" else -7.0
			var pitch := randf_range(0.76, 0.90)
			SynthAudio.play_3d(clip, stalker_node.global_position + Vector3(0, 1.8, 0), vol, pitch)


func _nearest_nav_idx(pos: Vector3) -> int:
	var space := get_world_3d().direct_space_state
	var from := Vector3(pos.x, 1.45, pos.z)
	var ex: Array[RID] = []
	if stalker_body != null:
		ex.append(stalker_body.get_rid())
	if local_player != null:
		ex.append(local_player.get_rid())
	var best_i := 0
	var best_score := 999999.0
	for i in range(nav_nodes.size()):
		var d := pos.distance_to(nav_nodes[i])
		var score := d
		if d > 0.5 and d < 18.0:
			var q := PhysicsRayQueryParameters3D.create(from, Vector3(nav_nodes[i].x, 1.45, nav_nodes[i].z))
			q.collision_mask = 1
			q.exclude = ex
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var col := hit.get("collider") as Node
				if col == null or str(col.get_meta("interact_type", "")) != "door":
					score += 25.0
		if score < best_score:
			best_score = score
			best_i = i
	return best_i


func _grid_to_world(gx: int, gz: int) -> Vector3:
	return Vector3(GRID_MIN_X + (float(gx) + 0.5) * GRID_CELL, 0.0, GRID_MIN_Z + (float(gz) + 0.5) * GRID_CELL)


func _world_to_grid(pos: Vector3) -> Vector2i:
	var gx := clampi(int(floor((pos.x - GRID_MIN_X) / GRID_CELL)), 0, GRID_W - 1)
	var gz := clampi(int(floor((pos.z - GRID_MIN_Z) / GRID_CELL)), 0, GRID_H - 1)
	return Vector2i(gx, gz)


func _is_grid_cell_walkable(gx: int, gz: int) -> bool:
	if gx < 0 or gx >= GRID_W or gz < 0 or gz >= GRID_H:
		return false
	return _grid_walkable[gz * GRID_W + gx] != 0


func _bake_walkability_grid() -> void:
	if not is_inside_tree() or get_world_3d() == null:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return

	_door_ex_rids.clear()
	for d in doors_ref:
		var col := d.get("collider") as CollisionObject3D
		if col != null and is_instance_valid(col):
			_door_ex_rids.append(col.get_rid())

	var ex: Array[RID] = []
	if stalker_body != null:
		ex.append(stalker_body.get_rid())
	if local_player != null:
		ex.append(local_player.get_rid())
	for drid in _door_ex_rids:
		ex.append(drid)

	var cyl := CylinderShape3D.new()
	cyl.radius = 0.44
	cyl.height = 1.6

	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cyl
	q.collision_mask = 1
	q.exclude = ex

	var total := GRID_W * GRID_H
	_grid_walkable.resize(total)
	_grid_near_blocked.resize(total)

	for gz in range(GRID_H):
		var wz := GRID_MIN_Z + (float(gz) + 0.5) * GRID_CELL
		var row_off := gz * GRID_W
		for gx in range(GRID_W):
			var wx := GRID_MIN_X + (float(gx) + 0.5) * GRID_CELL
			q.transform = Transform3D(Basis.IDENTITY, Vector3(wx, 0.90, wz))
			var hits := space.intersect_shape(q, 1)
			_grid_walkable[row_off + gx] = 1 if hits.is_empty() else 0

	# Force nav_node centers & strictly narrow clear-passage doorway cells walkable
	for np in nav_nodes:
		var nc := _world_to_grid(np)
		_grid_walkable[nc.y * GRID_W + nc.x] = 1

	for d in doors_ref:
		var dp: Vector3 = d["world_pos"]
		var d_dir: Vector3 = d.get("dir", Vector3(1.0, 0.0, 0.0))
		var d_norm: Vector3 = d.get("normal", Vector3(0.0, 0.0, 1.0))
		var dc := _world_to_grid(dp)

		var min_lat := 999.0
		for dz in range(-2, 3):
			var nz := dc.y + dz
			if nz < 0 or nz >= GRID_H:
				continue
			var wz := GRID_MIN_Z + (float(nz) + 0.5) * GRID_CELL
			for dx in range(-2, 3):
				var nx := dc.x + dx
				if nx < 0 or nx >= GRID_W:
					continue
				var wx := GRID_MIN_X + (float(nx) + 0.5) * GRID_CELL
				var rel := Vector3(wx - dp.x, 0.0, wz - dp.z)
				if absf(rel.dot(d_norm)) <= 0.90:
					min_lat = minf(min_lat, absf(rel.dot(d_dir)))

		var lat_tol := 0.30 if min_lat <= 0.305 else minf(min_lat + 0.02, 0.42)
		for dz in range(-2, 3):
			var nz := dc.y + dz
			if nz < 0 or nz >= GRID_H:
				continue
			var wz := GRID_MIN_Z + (float(nz) + 0.5) * GRID_CELL
			for dx in range(-2, 3):
				var nx := dc.x + dx
				if nx < 0 or nx >= GRID_W:
					continue
				var wx := GRID_MIN_X + (float(nx) + 0.5) * GRID_CELL
				var rel := Vector3(wx - dp.x, 0.0, wz - dp.z)
				if absf(rel.dot(d_dir)) <= lat_tol and absf(rel.dot(d_norm)) <= 0.90:
					_grid_walkable[nz * GRID_W + nx] = 1

	for gz in range(GRID_H):
		for gx in range(GRID_W):
			var idx := gz * GRID_W + gx
			if _grid_walkable[idx] == 0:
				_grid_near_blocked[idx] = 1
				continue
			var near := 0
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dz == 0:
						continue
					if not _is_grid_cell_walkable(gx + dx, gz + dz):
						near = 1
						break
				if near == 1:
					break
			_grid_near_blocked[idx] = near

	_grid_baked = true


func _find_nearest_walkable_cell(cell: Vector2i, max_radius: int = 4) -> Vector2i:
	if _is_grid_cell_walkable(cell.x, cell.y):
		return cell
	var best := Vector2i(-1, -1)
	var best_d2 := 999999
	for r in range(1, max_radius + 1):
		for dz in range(-r, r + 1):
			var nz := cell.y + dz
			if nz < 0 or nz >= GRID_H:
				continue
			for dx in range(-r, r + 1):
				var nx := cell.x + dx
				if nx < 0 or nx >= GRID_W:
					continue
				if _grid_walkable[nz * GRID_W + nx] != 0:
					var d2 := dx * dx + dz * dz
					if d2 < best_d2:
						best_d2 = d2
						best = Vector2i(nx, nz)
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func _astar_heap_push(heap_idx: Array[int], heap_f: Array[float], node_idx: int, f_val: float) -> void:
	heap_idx.append(node_idx)
	heap_f.append(f_val)
	var i := heap_idx.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if heap_f[p] <= heap_f[i]:
			break
		var ti := heap_idx[p]
		var tf := heap_f[p]
		heap_idx[p] = heap_idx[i]
		heap_f[p] = heap_f[i]
		heap_idx[i] = ti
		heap_f[i] = tf
		i = p


func _astar_heap_pop(heap_idx: Array[int], heap_f: Array[float]) -> int:
	var top := heap_idx[0]
	var last_i: int = int(heap_idx.pop_back())
	var last_f: float = float(heap_f.pop_back())
	var sz := heap_idx.size()
	if sz > 0:
		heap_idx[0] = last_i
		heap_f[0] = last_f
		var i := 0
		while true:
			var l := i * 2 + 1
			if l >= sz:
				break
			var r := l + 1
			var smallest := l
			if r < sz and heap_f[r] < heap_f[l]:
				smallest = r
			if heap_f[i] <= heap_f[smallest]:
				break
			var ti := heap_idx[i]
			var tf := heap_f[i]
			heap_idx[i] = heap_idx[smallest]
			heap_f[i] = heap_f[smallest]
			heap_idx[smallest] = ti
			heap_f[smallest] = tf
			i = smallest
	return top


func _grid_line_walkable(a: Vector2i, b: Vector2i) -> bool:
	var x := a.x
	var z := a.y
	if not _is_grid_cell_walkable(x, z) or not _is_grid_cell_walkable(b.x, b.y):
		return false
	var dx := b.x - a.x
	var dz := b.y - a.y
	if dx == 0 and dz == 0:
		return true
	var sx := 1 if dx > 0 else (-1 if dx < 0 else 0)
	var sz := 1 if dz > 0 else (-1 if dz < 0 else 0)
	var adx := absi(dx)
	var adz := absi(dz)
	var t_max_x := 0.5 / float(adx) if adx > 0 else 1e9
	var t_max_z := 0.5 / float(adz) if adz > 0 else 1e9
	var t_delta_x := 1.0 / float(adx) if adx > 0 else 1e9
	var t_delta_z := 1.0 / float(adz) if adz > 0 else 1e9

	while x != b.x or z != b.y:
		if absf(t_max_x - t_max_z) < 0.0001:
			if not _is_grid_cell_walkable(x + sx, z) or not _is_grid_cell_walkable(x, z + sz):
				return false
			x += sx
			z += sz
			t_max_x += t_delta_x
			t_max_z += t_delta_z
		elif t_max_x < t_max_z:
			x += sx
			t_max_x += t_delta_x
		else:
			z += sz
			t_max_z += t_delta_z
		if not _is_grid_cell_walkable(x, z):
			return false
	return true


func _build_grid_path(start_pos: Vector3, dest_pos: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not _grid_baked:
		return out
	var raw_goal_cell := _world_to_grid(dest_pos)
	var s_cell := _find_nearest_walkable_cell(_world_to_grid(start_pos), 4)
	var g_cell := _find_nearest_walkable_cell(raw_goal_cell, 4)
	if s_cell.x < 0 or g_cell.x < 0:
		return out

	var goal_world := Vector3(dest_pos.x, 0.0, dest_pos.z)
	var raw_goal_walkable := _is_grid_cell_walkable(raw_goal_cell.x, raw_goal_cell.y)
	if s_cell == g_cell:
		out.append(goal_world if (raw_goal_walkable or _has_clear_body_path(goal_world)) else _grid_to_world(g_cell.x, g_cell.y))
		return out

	var total := GRID_W * GRID_H
	var g_score := PackedFloat32Array()
	g_score.resize(total)
	g_score.fill(1e9)
	var parent := PackedInt32Array()
	parent.resize(total)
	parent.fill(-1)
	var closed := PackedByteArray()
	closed.resize(total)
	closed.fill(0)

	var s_idx := s_cell.y * GRID_W + s_cell.x
	var g_idx := g_cell.y * GRID_W + g_cell.x
	g_score[s_idx] = 0.0

	var heap_idx: Array[int] = []
	var heap_f: Array[float] = []
	var h0_dx := absf(float(g_cell.x - s_cell.x))
	var h0_dz := absf(float(g_cell.y - s_cell.y))
	_astar_heap_push(heap_idx, heap_f, s_idx, (h0_dx + h0_dz) + (1.4142135 - 2.0) * minf(h0_dx, h0_dz))

	var dir_x: Array[int] = [-1, 0, 1, -1, 1, -1, 0, 1]
	var dir_z: Array[int] = [-1, -1, -1, 0, 0, 1, 1, 1]
	var dir_c: Array[float] = [1.4142135, 1.0, 1.4142135, 1.0, 1.0, 1.4142135, 1.0, 1.4142135]

	var found := false
	while not heap_idx.is_empty():
		var cur := _astar_heap_pop(heap_idx, heap_f)
		if cur == g_idx:
			found = true
			break
		if closed[cur] != 0:
			continue
		closed[cur] = 1

		var cx := cur % GRID_W
		var cz := floori(float(cur) / float(GRID_W))
		var cur_g := g_score[cur]

		for k in range(8):
			var dx := dir_x[k]
			var dz := dir_z[k]
			var nx := cx + dx
			var nz := cz + dz
			if nx < 0 or nx >= GRID_W or nz < 0 or nz >= GRID_H:
				continue
			var n_idx := nz * GRID_W + nx
			if _grid_walkable[n_idx] == 0 or closed[n_idx] != 0:
				continue
			if dx != 0 and dz != 0:
				if _grid_walkable[cz * GRID_W + nx] == 0 or _grid_walkable[nz * GRID_W + cx] == 0:
					continue
			var step_cost := dir_c[k] + (0.8 if _grid_near_blocked[n_idx] != 0 else 0.0)
			var ng := cur_g + step_cost
			if ng < g_score[n_idx]:
				g_score[n_idx] = ng
				parent[n_idx] = cur
				var hdx := absf(float(g_cell.x - nx))
				var hdz := absf(float(g_cell.y - nz))
				var h := (hdx + hdz) + (1.4142135 - 2.0) * minf(hdx, hdz)
				_astar_heap_push(heap_idx, heap_f, n_idx, ng + h)

	if not found:
		return out

	var cells: Array[Vector2i] = []
	var trace := g_idx
	while trace != -1:
		cells.append(Vector2i(trace % GRID_W, floori(float(trace) / float(GRID_W))))
		trace = parent[trace]
	cells.reverse()

	var smoothed: Array[Vector2i] = []
	var anchor := 0
	smoothed.append(cells[0])
	while anchor < cells.size() - 1:
		var furthest := anchor + 1
		var probe := cells.size() - 1
		while probe > anchor + 1:
			if _grid_line_walkable(cells[anchor], cells[probe]):
				furthest = probe
				break
			probe -= 1
		smoothed.append(cells[furthest])
		anchor = furthest

	for i in range(1, smoothed.size()):
		out.append(_grid_to_world(smoothed[i].x, smoothed[i].y))

	if out.is_empty():
		out.append(_grid_to_world(g_cell.x, g_cell.y))
	elif raw_goal_walkable:
		out[out.size() - 1] = goal_world
	return out


func _steer_with_whiskers(desired_dir: Vector3) -> Vector3:
	if stalker_node == null or not is_inside_tree() or get_world_3d() == null:
		return desired_dir
	var space := get_world_3d().direct_space_state
	if space == null:
		return desired_dir

	var origin := Vector3(stalker_node.global_position.x, 0.65, stalker_node.global_position.z)
	var ex: Array[RID] = []
	if stalker_body != null:
		ex.append(stalker_body.get_rid())
	if local_player != null:
		ex.append(local_player.get_rid())
	for drid in _door_ex_rids:
		ex.append(drid)

	var feeler_len := 1.15
	var left_dir := desired_dir.rotated(Vector3.UP, deg_to_rad(-35.0))
	var right_dir := desired_dir.rotated(Vector3.UP, deg_to_rad(35.0))
	var dirs: Array[Vector3] = [left_dir, desired_dir, right_dir]
	var clears: Array[float] = [1.0, 1.0, 1.0]

	for i in range(3):
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dirs[i] * feeler_len)
		q.collision_mask = 1
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var hit_pos: Vector3 = hit["position"]
			clears[i] = clampf(origin.distance_to(hit_pos) / feeler_len, 0.0, 1.0)

	if clears[0] >= 0.99 and clears[1] >= 0.99 and clears[2] >= 0.99:
		return desired_dir

	var right_vec := Vector3(-desired_dir.z, 0.0, desired_dir.x)
	var push := 0.0
	if clears[0] < 1.0:
		push += (1.0 - clears[0]) * 1.15
	if clears[2] < 1.0:
		push -= (1.0 - clears[2]) * 1.15
	if clears[1] < 0.85:
		var center_push := (0.85 - clears[1]) * 1.45
		push += center_push if clears[2] >= clears[0] else -center_push

	var steered := desired_dir + right_vec * push
	steered.y = 0.0
	if steered.length_squared() < 0.0001:
		return desired_dir
	return steered.normalized()


func _generate_search_points(origin: Vector3, count: int) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	if not _grid_baked:
		return pts
	var base_ang := randf() * TAU
	for i in range(count):
		var ang := base_ang + (TAU * float(i) / float(maxi(count, 1))) + randf_range(-0.35, 0.35)
		var rad := randf_range(3.0, 5.8)
		var cand := Vector3(origin.x + cos(ang) * rad, 0.0, origin.z + sin(ang) * rad)
		var cell := _find_nearest_walkable_cell(_world_to_grid(cand), 2)
		if cell.x < 0:
			continue
		var wpt := _grid_to_world(cell.x, cell.y)
		if wpt.distance_to(origin) < 1.6:
			continue
		if not _build_grid_path(origin, wpt).is_empty():
			pts.append(wpt)
	return pts


func _build_nav_path_to(dest: Vector3) -> void:
	_current_path.clear()
	if _grid_baked and stalker_node != null:
		var grid_path := _build_grid_path(stalker_node.global_position, dest)
		if not grid_path.is_empty():
			_current_path = grid_path
			return
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
