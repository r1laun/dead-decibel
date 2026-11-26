class_name ListenerPlayer
extends CharacterBody3D

signal interact_requested(aim_origin: Vector3, aim_dir: Vector3)
signal item_dropped(item_id: String, drop_origin: Vector3, throw_vel: Vector3, is_thrown_bottle: bool)
signal flare_deployed(origin: Vector3, throw_vel: Vector3)
signal toggle_dossier_requested
signal inventory_changed
signal consumable_used(toast_key: String)

const WALK_SPEED := 3.65
const SPRINT_SPEED := 6.20
const CROUCH_SPEED := 2.05
const DOWNED_SPEED := 1.05
const GRAVITY := 18.0
const MAX_SLOTS := 5

const BASE_FOV := 74.0
const SPRINT_FOV := 79.0
const CROUCH_FOV := 70.0
const FOCUS_FOV := 66.0
const MOVE_ACCEL := 18.0
const MOVE_DECEL := 14.5
const JOY_DEADZONE_MOVE := 0.18
const JOY_DEADZONE_LOOK := 0.16
const TOUCH_WALK_DEADZONE := 0.08
const TOUCH_SPRINT_THRESHOLD := 0.90

var col_shape: CollisionShape3D
var capsule: CapsuleShape3D
var head: Node3D
var camera: Camera3D
var flashlight: SpotLight3D
var ambient_fill: OmniLight3D
var hand_mount: Node3D
var _held_mesh: Node3D = null

# Unified Touch + Desktop + Gamepad Input
var controls_enabled: bool = true
var touch_move_vec: Vector2 = Vector2.ZERO
var touch_sprinting: bool = false
var touch_holding_breath: bool = false
var is_crouching: bool = false
var flashlight_on: bool = true
var battery_charge: float = 1.0 # 0..1 (with emergency dynamo floor so never time-limited)

# Stealth, Breath & Time-Free Wound State
var is_hiding_in_locker: bool = false
var current_locker_id: String = ""
var locker_base_yaw: float = 0.0
var is_under_desk: bool = false
var is_holding_breath: bool = false
var breath_stamina: float = 1.0
var _breath_exhausted: bool = false

var wounds: int = 0
var is_caged: bool = false
var is_downed: bool = false
var downed_timer: float = 90.0
var is_dead: bool = false
var adrenaline_timer: float = 0.0
var known_safe_code: String = ""

# 5-Slot Inventory
var inventory: Array[String] = []
var selected_slot: int = 0

var _bob_time: float = 0.0
var _step_accum: float = 0.0
var _net_sync_timer: float = 0.0
var _hand_swing: float = 0.0
var _cam_trauma: float = 0.0

var _look_sway: Vector2 = Vector2.ZERO
var _sway_smooth: Vector2 = Vector2.ZERO
var _idle_breath_t: float = 0.0
var _breath_sway_amp: float = 1.0
var _cam_bob_offset: Vector2 = Vector2.ZERO
var _cam_roll: float = 0.0
var _flash_aim_yaw: float = 0.0
var _flash_aim_pitch: float = 0.0
var _flash_flicker_t: float = 0.0
var _joy_sprint_toggled: bool = false
var _was_moving_for_sprint: bool = false
var _joy_rt_held: bool = false
var _cage_wakeup_timer: float = 0.0
var _cage_wakeup_duration: float = 2.2
var _chase_tension: float = 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 16

	col_shape = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.70
	col_shape.shape = capsule
	col_shape.position = Vector3(0, 0.85, 0)
	add_child(col_shape)

	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.56, 0)
	add_child(head)

	camera = Camera3D.new()
	camera.fov = BASE_FOV
	camera.near = 0.05
	camera.far = 68.0
	head.add_child(camera)

	flashlight = SpotLight3D.new()
	flashlight.light_color = Color(1.0, 0.93, 0.80)
	flashlight.light_energy = 2.50
	flashlight.spot_range = 19.5
	flashlight.spot_angle = 37.0
	flashlight.spot_attenuation = 1.32
	flashlight.shadow_enabled = false
	flashlight.light_cull_mask = 1
	flashlight.position = Vector3(0.14, -0.10, -0.12)
	camera.add_child(flashlight)

	ambient_fill = OmniLight3D.new()
	ambient_fill.light_color = Color(0.65, 0.72, 0.82)
	ambient_fill.light_energy = 0.24
	ambient_fill.omni_range = 3.8
	ambient_fill.light_cull_mask = 1
	camera.add_child(ambient_fill)

	var vm_light := OmniLight3D.new()
	vm_light.light_color = Color(1.0, 0.92, 0.80)
	vm_light.light_energy = 0.22
	vm_light.omni_range = 1.6
	vm_light.light_cull_mask = 2
	vm_light.position = Vector3(-0.12, 0.18, -0.10)
	camera.add_child(vm_light)

	hand_mount = Node3D.new()
	hand_mount.position = Vector3(0.27, -0.25, -0.48)
	camera.add_child(hand_mount)

	_flash_aim_yaw = rotation.y
	_flash_aim_pitch = head.rotation.x

	for i in range(MAX_SLOTS):
		inventory.append("")


func reset_for_new_day(spawn_pos: Vector3, clear_items: bool = false) -> void:
	global_position = spawn_pos
	velocity = Vector3.ZERO
	is_hiding_in_locker = false
	current_locker_id = ""
	is_under_desk = false
	is_holding_breath = false
	breath_stamina = 1.0
	_breath_exhausted = false
	is_downed = false
	downed_timer = 90.0
	is_dead = false
	is_crouching = false
	col_shape.disabled = false
	flashlight_on = true
	battery_charge = maxf(battery_charge, 0.65)
	_bob_time = 0.0
	_step_accum = 0.0
	_hand_swing = 0.0
	_cam_trauma = 0.0
	_look_sway = Vector2.ZERO
	_sway_smooth = Vector2.ZERO
	_cam_bob_offset = Vector2.ZERO
	_cam_roll = 0.0
	_joy_sprint_toggled = false
	_was_moving_for_sprint = false
	_joy_rt_held = false
	_cage_wakeup_timer = 0.0
	_cage_wakeup_duration = 2.2
	_chase_tension = 0.0
	_flash_aim_yaw = rotation.y
	_flash_aim_pitch = head.rotation.x
	camera.position = Vector3.ZERO
	camera.rotation.z = 0.0
	camera.fov = BASE_FOV
	flashlight.rotation = Vector3.ZERO
	ambient_fill.light_energy = 0.24
	ambient_fill.omni_range = 3.8
	if clear_items:
		wounds = 0
		is_caged = false
		known_safe_code = ""
		battery_charge = 1.0
		for i in range(MAX_SLOTS):
			inventory[i] = ""
		selected_slot = 0
		_refresh_held_model()
		inventory_changed.emit()


func add_camera_trauma(amount: float) -> void:
	if SaveState.reduce_motion:
		return
	_cam_trauma = clampf(_cam_trauma + amount, 0.0, 1.0)


func set_chase_tension(in_chase: bool, monster_dist: float) -> void:
	if not in_chase or monster_dist >= 14.0 or SaveState.reduce_motion:
		_chase_tension = 0.0
		return
	_chase_tension = clampf(1.0 - (monster_dist / 14.0), 0.0, 1.0)


func start_cage_wakeup(duration: float = 2.2) -> void:
	if DisplayServer.get_name() == "headless" or duration <= 0.05:
		_cage_wakeup_timer = 0.0
		head.position.y = 1.56
		head.rotation.x = 0.0
		_cam_roll = 0.0
		camera.rotation.z = 0.0
		return
	_cage_wakeup_duration = maxf(0.1, duration)
	_cage_wakeup_timer = _cage_wakeup_duration
	head.position.y = 0.36
	head.rotation.x = -0.22
	if SaveState.reduce_motion:
		_cam_roll = 0.0
		camera.rotation.z = 0.0
	else:
		_cam_roll = 0.24
		camera.rotation.z = 0.24


func get_equipped_item() -> String:
	if selected_slot >= 0 and selected_slot < inventory.size():
		return inventory[selected_slot]
	return ""


func has_item_in_inventory(item_id: String) -> int:
	for i in range(MAX_SLOTS):
		if inventory[i] == item_id:
			return i
	return -1


func consume_item_by_id(item_id: String) -> bool:
	var idx := has_item_in_inventory(item_id)
	if idx < 0:
		return false
	inventory[idx] = ""
	_refresh_held_model()
	inventory_changed.emit()
	return true


func select_slot(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= MAX_SLOTS:
		return
	selected_slot = slot_idx
	_refresh_held_model()
	inventory_changed.emit()


func add_item_to_inventory(item_id: String) -> bool:
	if inventory[selected_slot].is_empty():
		inventory[selected_slot] = item_id
		_refresh_held_model()
		inventory_changed.emit()
		return true
	for i in range(MAX_SLOTS):
		if inventory[i].is_empty():
			inventory[i] = item_id
			selected_slot = i
			_refresh_held_model()
			inventory_changed.emit()
			return true
	return false


func consume_equipped_item() -> void:
	if selected_slot >= 0 and selected_slot < MAX_SLOTS:
		inventory[selected_slot] = ""
		_refresh_held_model()
		inventory_changed.emit()


func _refresh_held_model() -> void:
	if _held_mesh != null:
		_held_mesh.queue_free()
		_held_mesh = null
	var item_id := get_equipped_item()
	if item_id.is_empty():
		return
	_held_mesh = AssetLibrary.instantiate_model("item_" + item_id)
	var vm_scale := 0.58
	if item_id in ["medkit", "code_note"]:
		vm_scale = 0.44
	elif item_id in ["cutters", "crowbar"]:
		vm_scale = 0.52
	_held_mesh.scale = Vector3.ONE * vm_scale
	if item_id in ["medkit", "code_note"]:
		_held_mesh.rotation_degrees = Vector3(54.0, -18.0, 12.0)
	elif item_id == "flare":
		_held_mesh.rotation_degrees = Vector3(14.0, 32.0, -38.0)
	else:
		_held_mesh.rotation_degrees = Vector3(28.0, 56.0, -16.0)
	_configure_viewmodel_mesh(_held_mesh)
	hand_mount.add_child(_held_mesh)


func _configure_viewmodel_mesh(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = 2
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for ch in n.get_children():
		_configure_viewmodel_mesh(ch)


func apply_look_delta(rel: Vector2) -> void:
	if not controls_enabled or is_dead:
		return
	var sens := 0.0028 * SaveState.look_sensitivity
	_look_sway = (_look_sway + rel * 0.0020 * SaveState.look_sensitivity).clamp(Vector2(-0.18, -0.18), Vector2(0.18, 0.18))
	if is_hiding_in_locker:
		var next_yaw := rotation.y - rel.x * sens
		var diff := angle_difference(locker_base_yaw, next_yaw)
		rotation.y = locker_base_yaw + clampf(diff, -0.52, 0.52)
		head.rotation.x = clampf(head.rotation.x - rel.y * sens, -0.38, 0.38)
		return
	rotate_y(-rel.x * sens)
	head.rotation.x = clampf(head.rotation.x - rel.y * sens, -1.35, 1.35)


func toggle_crouch() -> void:
	if is_hiding_in_locker or is_downed:
		return
	is_crouching = not is_crouching
	if is_crouching:
		_joy_sprint_toggled = false


func toggle_flashlight() -> void:
	flashlight_on = not flashlight_on
	SynthAudio.play_2d("flashlight_click", -5.0)


func enter_locker(locker_id: String, inside_pos: Vector3, look_yaw: float) -> void:
	is_hiding_in_locker = true
	current_locker_id = locker_id
	locker_base_yaw = look_yaw
	velocity = Vector3.ZERO
	_joy_sprint_toggled = false
	col_shape.disabled = true
	global_position = inside_pos
	rotation.y = look_yaw
	head.rotation.x = 0.0
	head.position.y = 1.54
	_flash_aim_yaw = look_yaw
	_flash_aim_pitch = 0.0


func exit_locker(exit_pos: Vector3) -> void:
	is_hiding_in_locker = false
	current_locker_id = ""
	col_shape.disabled = false
	global_position = exit_pos
	velocity = Vector3.ZERO
	_flash_aim_yaw = rotation.y
	_flash_aim_pitch = head.rotation.x


func trigger_interact() -> void:
	if not controls_enabled or is_dead:
		return
	_hand_swing = 1.0
	var aim_origin := camera.global_position
	var aim_dir := -camera.global_transform.basis.z
	interact_requested.emit(aim_origin, aim_dir)


func quick_reload_battery() -> bool:
	if not controls_enabled or is_dead or is_downed:
		return false
	if consume_item_by_id("battery"):
		battery_charge = 1.0
		flashlight_on = true
		_hand_swing = 0.65
		SynthAudio.play_2d("flashlight_click", -2.0, 1.25)
		consumable_used.emit("TOAST_BATTERY_USED")
		return true
	return false


func use_or_throw_equipped() -> bool:
	if not controls_enabled or is_dead:
		return false
	var item := get_equipped_item()
	if item.is_empty():
		return false
	if is_hiding_in_locker:
		if item in ["battery", "syringe", "medkit"]:
			return try_use_held_consumable()
		return false
	if is_downed:
		if item in ["syringe", "medkit"]:
			return try_use_held_consumable()
		return false
	if item == "bottle":
		drop_or_throw_equipped()
		return true
	if item in ["battery", "syringe", "medkit", "flare"]:
		return try_use_held_consumable()
	return false


func try_use_held_consumable() -> bool:
	var item := get_equipped_item()
	if item == "battery":
		battery_charge = 1.0
		flashlight_on = true
		consume_equipped_item()
		SynthAudio.play_2d("flashlight_click", -2.0, 1.25)
		consumable_used.emit("TOAST_BATTERY_USED")
		return true
	elif item == "syringe":
		adrenaline_timer = 10.0
		is_downed = false
		downed_timer = 90.0
		consume_equipped_item()
		SynthAudio.play_2d("item_pickup", -2.0, 1.35)
		consumable_used.emit("TOAST_SYRINGE_USED")
		return true
	elif item == "medkit":
		wounds = 0
		is_downed = false
		downed_timer = 90.0
		breath_stamina = 1.0
		consume_equipped_item()
		SynthAudio.play_2d("item_pickup", -1.5, 1.12)
		consumable_used.emit("TOAST_MEDKIT_USED")
		return true
	elif item == "flare":
		consume_equipped_item()
		_hand_swing = 1.0
		var fwd := -camera.global_transform.basis.z
		var origin := camera.global_position + fwd * 0.55 + Vector3(0, -0.10, 0)
		flare_deployed.emit(origin, fwd * 11.5 + Vector3(0, 2.0, 0))
		consumable_used.emit("TOAST_FLARE_USED")
		return true
	return false


func drop_or_throw_equipped() -> void:
	if not controls_enabled or is_dead or is_hiding_in_locker or is_downed:
		return
	var item := get_equipped_item()
	if item.is_empty():
		return
	consume_equipped_item()
	_hand_swing = 1.0
	var fwd := -camera.global_transform.basis.z
	var origin := camera.global_position + fwd * 0.55 + Vector3(0, -0.12, 0)
	if item == "flare":
		flare_deployed.emit(origin, fwd * 11.5 + Vector3(0, 2.0, 0))
		consumable_used.emit("TOAST_FLARE_USED")
	elif item == "bottle":
		item_dropped.emit(item, origin, fwd * 12.5 + Vector3(0, 2.2, 0), true)
	else:
		item_dropped.emit(item, origin, fwd * 3.2 + Vector3(0, 0.8, 0), false)


func is_stealth_hidden() -> bool:
	return is_hiding_in_locker or (is_crouching and is_under_desk)


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled or is_dead:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		apply_look_delta((event as InputEventMouseMotion).relative)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			trigger_interact()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			use_or_throw_equipped()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			select_slot((selected_slot + MAX_SLOTS - 1) % MAX_SLOTS)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select_slot((selected_slot + 1) % MAX_SLOTS)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			match k.keycode:
				KEY_E:
					trigger_interact()
				KEY_F:
					toggle_flashlight()
				KEY_R:
					quick_reload_battery()
				KEY_C, KEY_CTRL:
					toggle_crouch()
				KEY_G, KEY_Q:
					drop_or_throw_equipped()
				KEY_TAB, KEY_J:
					toggle_dossier_requested.emit()
				KEY_1:
					select_slot(0)
				KEY_2:
					select_slot(1)
				KEY_3:
					select_slot(2)
				KEY_4:
					select_slot(3)
				KEY_5:
					select_slot(4)
		if k.keycode == KEY_V:
			AcousticBus.ptt_held = k.pressed
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.pressed and not jb.is_echo():
			match jb.button_index:
				JOY_BUTTON_A, JOY_BUTTON_X:
					trigger_interact()
				JOY_BUTTON_B:
					toggle_crouch()
				JOY_BUTTON_Y:
					toggle_flashlight()
				JOY_BUTTON_LEFT_SHOULDER:
					select_slot((selected_slot + MAX_SLOTS - 1) % MAX_SLOTS)
				JOY_BUTTON_RIGHT_SHOULDER:
					select_slot((selected_slot + 1) % MAX_SLOTS)
				JOY_BUTTON_DPAD_DOWN:
					drop_or_throw_equipped()
				JOY_BUTTON_DPAD_UP:
					quick_reload_battery()
				JOY_BUTTON_BACK:
					toggle_dossier_requested.emit()
				JOY_BUTTON_LEFT_STICK:
					_joy_sprint_toggled = not _joy_sprint_toggled


func _poll_gamepad_axes() -> Dictionary:
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty():
		return {
			"move": Vector2.ZERO,
			"look": Vector2.ZERO,
			"hold_breath": false,
			"rt": false
		}
	var best_ls := Vector2.ZERO
	var best_rs := Vector2.ZERO
	var lt_max := 0.0
	var rt_max := 0.0
	for dev in pads:
		var ls := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		if ls.length() > best_ls.length():
			best_ls = ls
		var rs := Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
		if rs.length() > best_rs.length():
			best_rs = rs
		lt_max = maxf(lt_max, Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT))
		rt_max = maxf(rt_max, Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT))

	var move_out := Vector2.ZERO
	var ls_len := best_ls.length()
	if ls_len > JOY_DEADZONE_MOVE:
		var scaled := clampf((ls_len - JOY_DEADZONE_MOVE) / (1.0 - JOY_DEADZONE_MOVE), 0.0, 1.0)
		move_out = (best_ls / ls_len) * scaled

	var look_out := Vector2.ZERO
	var rs_len := best_rs.length()
	if rs_len > JOY_DEADZONE_LOOK:
		var scaled_r := clampf((rs_len - JOY_DEADZONE_LOOK) / (1.0 - JOY_DEADZONE_LOOK), 0.0, 1.0)
		look_out = (best_rs / rs_len) * pow(scaled_r, 1.45)

	return {
		"move": move_out,
		"look": look_out,
		"hold_breath": lt_max > 0.4,
		"rt": rt_max > 0.45
	}


func _update_breath_state(delta: float, joy_hold_breath: bool = false) -> void:
	var want_hold := (Input.is_key_pressed(KEY_SPACE) or touch_holding_breath or joy_hold_breath) and controls_enabled and not is_dead and not is_downed
	if _breath_exhausted:
		want_hold = false
		if breath_stamina >= 0.35:
			_breath_exhausted = false

	if want_hold and breath_stamina > 0.0:
		is_holding_breath = true
		breath_stamina = maxf(0.0, breath_stamina - delta * 0.16)
		if breath_stamina <= 0.001:
			is_holding_breath = false
			_breath_exhausted = true
			SynthAudio.play_2d("heartbeat", 0.0, 1.32)
			AcousticBus.emit_noise(global_position, 8.5, 0.48, "gasp")
			consumable_used.emit("TOAST_GASP")
	else:
		is_holding_breath = false
		breath_stamina = minf(1.0, breath_stamina + delta * 0.24)


func _update_flashlight_visuals(delta: float) -> void:
	var flash_alpha := 1.0 - exp(-delta / 0.068)
	_flash_aim_yaw = lerp_angle(_flash_aim_yaw, rotation.y, flash_alpha)
	_flash_aim_pitch = lerpf(_flash_aim_pitch, head.rotation.x, flash_alpha)
	var lag_yaw := clampf(angle_difference(rotation.y, _flash_aim_yaw), -0.15, 0.15)
	var lag_pitch := clampf(_flash_aim_pitch - head.rotation.x, -0.13, 0.13)
	_flash_aim_yaw = rotation.y + lag_yaw
	_flash_aim_pitch = head.rotation.x + lag_pitch

	var idle_beam_x := 0.0
	var idle_beam_y := 0.0
	if not SaveState.reduce_motion:
		idle_beam_x = cos(_idle_breath_t * 1.9) * 0.004 * _breath_sway_amp
		idle_beam_y = sin(_idle_breath_t * 1.35) * 0.004 * _breath_sway_amp
	flashlight.rotation = Vector3(lag_pitch + idle_beam_x, lag_yaw + idle_beam_y, 0.0)

	# Flashlight battery with emergency dynamo floor (never soft-locks over long runs!)
	if flashlight_on and not is_hiding_in_locker:
		if battery_charge > 0.24:
			battery_charge = maxf(0.24, battery_charge - delta * 0.0032)
		var pwr := lerpf(0.65, 2.50, clampf(battery_charge * 1.15, 0.0, 1.0))
		if battery_charge <= 0.25:
			_flash_flicker_t += delta
			if SaveState.reduce_motion:
				pwr *= 0.90 + 0.10 * sin(_flash_flicker_t * 3.2)
			else:
				var hf := sin(_flash_flicker_t * 37.0) * sin(_flash_flicker_t * 61.0)
				var dip := 0.42 if hf > 0.58 else (0.78 + 0.22 * sin(_flash_flicker_t * 19.0))
				pwr *= dip
			flashlight.light_color = Color(1.0, 0.88, 0.68)
		else:
			flashlight.light_color = Color(1.0, 0.93, 0.80)
		flashlight.light_energy = pwr
		flashlight.visible = true
	else:
		flashlight.visible = false
		if battery_charge < 0.30:
			battery_charge = minf(0.30, battery_charge + delta * 0.018)

	var target_fill_energy := 0.50 if is_hiding_in_locker else 0.24
	var target_fill_range := 8.0 if is_hiding_in_locker else 3.8
	var fill_alpha := 1.0 - exp(-delta * 6.0)
	ambient_fill.light_energy = lerpf(ambient_fill.light_energy, target_fill_energy, fill_alpha)
	ambient_fill.omni_range = lerpf(ambient_fill.omni_range, target_fill_range, fill_alpha)


func _update_viewmodel_kinematics(delta: float, horiz_spd: float, sprinting: bool, eff_crouch: bool) -> void:
	hand_mount.visible = not is_hiding_in_locker and not is_downed
	var sway_target := Vector2.ZERO if SaveState.reduce_motion else -_look_sway
	_sway_smooth = _sway_smooth.lerp(sway_target, 1.0 - exp(-delta * 12.0))
	_look_sway = _look_sway.lerp(Vector2.ZERO, 1.0 - exp(-delta * 16.0))

	var breath_target := 0.0 if (is_holding_breath or SaveState.reduce_motion) else 1.0
	_breath_sway_amp = lerpf(_breath_sway_amp, breath_target, 1.0 - exp(-delta * 8.0))

	var vm_bob_x := 0.0
	var vm_bob_y := 0.0
	if horiz_spd > 0.35 and is_on_floor() and not SaveState.reduce_motion:
		var vm_scale := 0.55 if eff_crouch else (1.25 if sprinting else 0.90)
		vm_bob_x = cos(_bob_time * 0.5) * 0.011 * vm_scale
		vm_bob_y = sin(_bob_time) * 0.014 * vm_scale

	var breath_x := sin(_idle_breath_t * 1.35) * 0.0045 * _breath_sway_amp
	var breath_y := cos(_idle_breath_t * 1.9) * 0.0055 * _breath_sway_amp
	var lag_x := clampf(_sway_smooth.x * 0.22, -0.035, 0.035)
	var lag_y := clampf(_sway_smooth.y * 0.18, -0.030, 0.030)
	var swing_dip := sin(_hand_swing * PI) * 0.038

	var target_pos := Vector3(
		0.27 + lag_x + vm_bob_x + breath_x,
		-0.25 + lag_y + vm_bob_y + breath_y - swing_dip,
		-0.48
	)
	hand_mount.position = hand_mount.position.lerp(target_pos, 1.0 - exp(-delta * 16.0))

	var swing_rot := sin(_hand_swing * PI) * 24.0
	var lag_pitch := clampf(_sway_smooth.y * 42.0, -7.0, 7.0)
	var lag_yaw := clampf(-_sway_smooth.x * 52.0, -9.0, 9.0)
	var lag_roll := clampf(-_sway_smooth.x * 24.0, -5.0, 5.0)
	hand_mount.rotation_degrees = Vector3(-swing_rot + lag_pitch, lag_yaw, lag_roll)


func _physics_process(delta: float) -> void:
	_idle_breath_t += delta
	var pad := _poll_gamepad_axes()
	var joy_look: Vector2 = pad["look"]
	if joy_look.length_squared() > 0.0001 and controls_enabled and not is_dead:
		apply_look_delta(joy_look * delta * 760.0)

	if SaveState.gyro_enabled and controls_enabled and not is_dead:
		var gyro := Input.get_gyroscope()
		if gyro.length_squared() > 0.0005:
			apply_look_delta(Vector2(-gyro.y * 16.0, -gyro.x * 16.0))

	var rt_now := bool(pad["rt"])
	if rt_now and not _joy_rt_held:
		use_or_throw_equipped()
	_joy_rt_held = rt_now

	adrenaline_timer = maxf(0.0, adrenaline_timer - delta)
	_hand_swing = move_toward(_hand_swing, 0.0, delta * 4.5)
	if SaveState.reduce_motion:
		_cam_trauma = 0.0
		_chase_tension = 0.0
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	else:
		_cam_trauma = move_toward(_cam_trauma, 0.0, delta * 2.4)
		var off_x := 0.0
		var off_y := 0.0
		if _cam_trauma > 0.001:
			var shake := _cam_trauma * _cam_trauma * 0.045
			off_x += randf_range(-shake, shake)
			off_y += randf_range(-shake, shake)
		if _chase_tension > 0.001 and controls_enabled and not is_dead:
			var panic_amp := _chase_tension * 0.0085
			off_x += sin(_idle_breath_t * 43.0) * panic_amp * 0.6 + randf_range(-panic_amp, panic_amp) * 0.5
			off_y += cos(_idle_breath_t * 51.0) * panic_amp * 0.6 + randf_range(-panic_amp, panic_amp) * 0.5
		camera.h_offset = off_x
		camera.v_offset = off_y

	_update_breath_state(delta, bool(pad["hold_breath"]))
	_update_flashlight_visuals(delta)

	if is_dead or not controls_enabled:
		_joy_sprint_toggled = false
		_update_viewmodel_kinematics(delta, 0.0, false, is_crouching or is_under_desk)
		return

	if is_hiding_in_locker:
		_joy_sprint_toggled = false
		_cam_bob_offset = _cam_bob_offset.lerp(Vector2.ZERO, 1.0 - exp(-delta * 12.0))
		camera.position.x = _cam_bob_offset.x
		camera.position.y = _cam_bob_offset.y
		_cam_roll = lerpf(_cam_roll, 0.0, 1.0 - exp(-delta * 12.0))
		camera.rotation.z = _cam_roll
		var locker_fov := FOCUS_FOV if (is_holding_breath and not SaveState.reduce_motion) else BASE_FOV
		camera.fov = lerpf(camera.fov, locker_fov, 1.0 - exp(-delta * 8.0))
		_update_viewmodel_kinematics(delta, 0.0, false, true)
		AcousticBus.set_listener_position(head.global_position)
		_sync_network(delta)
		return

	var target_cap_h := 1.70
	var target_head_y := 1.56
	if is_downed:
		target_cap_h = 0.75
		target_head_y = 0.52
	elif is_crouching or is_under_desk:
		target_cap_h = 0.84
		target_head_y = 0.72

	capsule.height = lerpf(capsule.height, target_cap_h, clampf(delta * 12.0, 0.0, 1.0))
	col_shape.position.y = capsule.height * 0.5
	var wakeup_roll_active := false
	if _cage_wakeup_timer > 0.0:
		var prev_p := 1.0 - (_cage_wakeup_timer / _cage_wakeup_duration)
		var prev_ease := prev_p * prev_p * (3.0 - 2.0 * prev_p)
		_cage_wakeup_timer = maxf(0.0, _cage_wakeup_timer - delta)
		var p := 1.0 - (_cage_wakeup_timer / _cage_wakeup_duration)
		var ease_p := p * p * (3.0 - 2.0 * p)
		head.position.y = lerpf(0.36, target_head_y, ease_p)
		head.rotation.x = clampf(head.rotation.x + (ease_p - prev_ease) * 0.22, -1.35, 1.35)
		if not SaveState.reduce_motion:
			wakeup_roll_active = true
			var groggy_sway := sin(p * PI * 2.0) * 0.045 * (1.0 - ease_p)
			_cam_roll = lerpf(0.24, 0.0, ease_p) + groggy_sway
			camera.rotation.z = _cam_roll
	else:
		head.position.y = lerpf(head.position.y, target_head_y, clampf(delta * 12.0, 0.0, 1.0))

	var kb := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		kb.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		kb.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		kb.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		kb.y += 1.0

	var touch_in := Vector2.ZERO
	var touch_raw_mag := touch_move_vec.length()
	var touch_sprint_active := false
	if touch_raw_mag >= TOUCH_WALK_DEADZONE:
		if touch_raw_mag >= TOUCH_SPRINT_THRESHOLD:
			touch_in = touch_move_vec.normalized()
			touch_sprint_active = touch_sprinting
		else:
			var walk_scale := clampf((touch_raw_mag - TOUCH_WALK_DEADZONE) / (TOUCH_SPRINT_THRESHOLD - TOUCH_WALK_DEADZONE), 0.0, 1.0)
			touch_in = touch_move_vec.normalized() * walk_scale

	var joy_move: Vector2 = pad["move"]
	var move_in := kb + touch_in + joy_move
	if move_in.length() > 1.0:
		move_in = move_in.normalized()

	var move_mag := move_in.length()
	if move_mag > 0.25:
		_was_moving_for_sprint = true
	elif _was_moving_for_sprint and move_mag < 0.12:
		_was_moving_for_sprint = false
		_joy_sprint_toggled = false

	var eff_crouch := is_crouching or is_under_desk
	if eff_crouch or is_downed:
		_joy_sprint_toggled = false
	var sprinting := (Input.is_key_pressed(KEY_SHIFT) or touch_sprint_active or _joy_sprint_toggled) and not eff_crouch and not is_downed and not is_holding_breath and move_mag > 0.25

	var spd := WALK_SPEED
	if is_downed:
		spd = DOWNED_SPEED
	elif eff_crouch:
		spd = CROUCH_SPEED
	elif sprinting:
		spd = SPRINT_SPEED
	if wounds > 0 and not is_downed and adrenaline_timer <= 0.0:
		spd *= 0.86
	if adrenaline_timer > 0.0 and not is_downed:
		spd *= 1.28

	var wish_dir := (global_transform.basis * Vector3(move_in.x, 0.0, move_in.y))
	wish_dir.y = 0.0
	if wish_dir.length() > 0.001:
		wish_dir = wish_dir.normalized()

	var target_vx := wish_dir.x * spd * move_mag
	var target_vz := wish_dir.z * spd * move_mag
	var has_wish := move_mag > 0.02
	var rate := MOVE_ACCEL if has_wish else MOVE_DECEL
	var vel_alpha := 1.0 - exp(-rate * delta)
	velocity.x = lerpf(velocity.x, target_vx, vel_alpha)
	velocity.z = lerpf(velocity.z, target_vz, vel_alpha)
	if not has_wish and Vector2(velocity.x, velocity.z).length() < 0.02:
		velocity.x = 0.0
		velocity.z = 0.0

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.1

	move_and_slide()
	AcousticBus.set_listener_position(head.global_position)

	var horiz_spd := Vector2(velocity.x, velocity.z).length()
	var target_fov := BASE_FOV
	if not SaveState.reduce_motion:
		if is_holding_breath:
			target_fov = FOCUS_FOV
		elif is_downed or eff_crouch:
			target_fov = CROUCH_FOV
		elif sprinting and horiz_spd > WALK_SPEED * 0.9:
			target_fov = lerpf(SPRINT_FOV, 82.0, _chase_tension)
		elif _chase_tension > 0.001:
			target_fov = lerpf(BASE_FOV, 77.5, _chase_tension)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-delta * 8.0))

	if not wakeup_roll_active:
		var target_roll := 0.0 if SaveState.reduce_motion else clampf(-move_in.x * deg_to_rad(1.2), -deg_to_rad(1.2), deg_to_rad(1.2))
		_cam_roll = lerpf(_cam_roll, target_roll, 1.0 - exp(-delta * 10.0))
		camera.rotation.z = _cam_roll

	if horiz_spd > 0.35 and is_on_floor():
		_bob_time += delta * horiz_spd * 2.2
		if not SaveState.reduce_motion:
			var bob_scale := 0.55 if eff_crouch else (1.15 if sprinting else 0.85)
			var target_bob := Vector2(cos(_bob_time * 0.5) * 0.013 * bob_scale, sin(_bob_time) * 0.021 * bob_scale)
			_cam_bob_offset = _cam_bob_offset.lerp(target_bob, 1.0 - exp(-delta * 14.0))
		else:
			_cam_bob_offset = _cam_bob_offset.lerp(Vector2.ZERO, 1.0 - exp(-delta * 14.0))

		_step_accum += horiz_spd * delta
		var stride := 1.45 if eff_crouch else (1.95 if sprinting else 1.70)
		if _step_accum >= stride:
			_step_accum = 0.0
			if eff_crouch or adrenaline_timer > 0.0:
				SynthAudio.play_2d("step_tile", -18.0, randf_range(0.85, 0.95))
				AcousticBus.current_noise_level = maxf(AcousticBus.current_noise_level, 0.07)
			elif sprinting:
				SynthAudio.play_2d("step_tile", -5.0, randf_range(1.02, 1.14))
				AcousticBus.emit_noise(global_position, 15.5, 0.80, "sprint")
			else:
				SynthAudio.play_2d("step_tile", -11.0, randf_range(0.94, 1.04))
				AcousticBus.emit_noise(global_position, 4.8, 0.24, "walk")
	else:
		_cam_bob_offset = _cam_bob_offset.lerp(Vector2.ZERO, 1.0 - exp(-delta * 10.0))

	camera.position.x = _cam_bob_offset.x
	camera.position.y = _cam_bob_offset.y
	_update_viewmodel_kinematics(delta, horiz_spd, sprinting, eff_crouch)

	_sync_network(delta)


func _sync_network(delta: float) -> void:
	_net_sync_timer += delta
	if _net_sync_timer >= 0.065:
		_net_sync_timer = 0.0
		NetRelay.broadcast_local_player_state({
			"callsign": SaveState.callsign,
			"pos": [snappedf(global_position.x, 0.01), snappedf(global_position.y, 0.01), snappedf(global_position.z, 0.01)],
			"yaw": snappedf(rotation.y, 0.01),
			"pitch": snappedf(head.rotation.x, 0.01),
			"crouch": is_crouching or is_under_desk,
			"hiding": is_hiding_in_locker,
			"downed": is_downed,
			"caged": is_caged,
			"wounds": wounds,
			"flash": flashlight_on,
			"item": get_equipped_item()
		})
