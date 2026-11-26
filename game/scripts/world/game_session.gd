class_name GameSession
extends Node3D

enum Phase { MAIN_MENU, PLAYING, TRANSITION, ENDED }

var phase: Phase = Phase.MAIN_MENU
var world_container: Node3D
var dynamic_root: Node3D
var player: ListenerPlayer
var monster_director: MonsterDirector
var hud: BrutalHud

# Menu Diorama refs
var _menu_cam: Camera3D = null
var _menu_stalker: Node3D = null
var _menu_time: float = 0.0

# Active Facility State (Zero Time Limit / Zero Day Cap!)
var current_seed: int = 10707
var current_difficulty: int = SaveState.DIFF_NORMAL
var match_elapsed_sec: float = 0.0

var safe_code: String = "4829"
var safe_opened: bool = false
var planks_removed: bool = false
var cable_cut: bool = false
var power_restored: bool = false
var padlock_unlocked: bool = false
var gate_opening: bool = false

var _map_data: Dictionary = {}
var _doors: Array[Dictionary] = []
var _vents: Dictionary = {}
var _pa_stations: Dictionary = {}
var _holding_cage: Dictionary = {}
var _glass_hazards: Array[Dictionary] = []
var _wheelchair_hazards: Array[Dictionary] = []
var _lockers: Dictionary = {}
var _hide_desks: Array[AABB] = []
var _cabinets: Dictionary = {}
var _flicker_lights: Array[Dictionary] = []
var _world_pickups: Dictionary = {}
var _flying_items: Array[Dictionary] = []
var _active_flares: Array[Dictionary] = []
var _next_pickup_seq: int = 1

var remote_listeners: Dictionary = {}
var _snapshot_sent: Dictionary = {}
var _jumpscare_active: bool = false
var _tut_start_pos: Vector3 = Vector3.ZERO
var _tut_prev_flashlight: bool = true
var _tut_prev_inv_count: int = 0


func _ready() -> void:
	if OS.get_name() in ["Android", "iOS"]:
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)

	world_container = Node3D.new()
	world_container.name = "WorldContainer"
	add_child(world_container)

	dynamic_root = Node3D.new()
	dynamic_root.name = "DynamicRoot"
	add_child(dynamic_root)

	player = ListenerPlayer.new()
	player.name = "LocalSurvivor"
	player.controls_enabled = false
	add_child(player)

	monster_director = MonsterDirector.new()
	monster_director.name = "MonsterDirector"
	monster_director.local_player = player
	monster_director.remote_players = remote_listeners
	add_child(monster_director)

	hud = BrutalHud.new()
	hud.name = "BrutalHud"
	add_child(hud)
	hud.bind_player(player)

	player.interact_requested.connect(_on_player_interact)
	player.item_dropped.connect(_on_player_item_dropped)
	player.flare_deployed.connect(_on_player_flare_deployed)
	monster_director.player_caught_by_stalker.connect(_on_local_player_caught)
	monster_director.door_smashed_nearby.connect(_on_door_smashed_nearby)

	hud.start_solo_requested.connect(_on_start_solo)
	hud.start_coop_match_requested.connect(_on_start_coop_host)
	hud.restart_match_requested.connect(_on_restart_requested)
	hud.return_to_menu_requested.connect(enter_main_menu)
	hud.safe_code_submitted.connect(_on_safe_code_submitted)

	NetRelay.peer_updated.connect(_on_peer_updated)
	NetRelay.peer_removed.connect(_on_peer_removed)
	NetRelay.peer_voice_received.connect(_on_peer_voice)
	NetRelay.remote_event_received.connect(_on_remote_event)
	NetRelay.room_left.connect(_on_room_left)
	NetRelay.host_migrated.connect(_on_host_migrated)
	Loc.language_changed.connect(_on_language_changed)

	enter_main_menu()


func _clear_world() -> void:
	monster_director.clear_stalker()
	for ch in world_container.get_children():
		ch.queue_free()
	for ch in dynamic_root.get_children():
		ch.queue_free()
	_world_pickups.clear()
	_flying_items.clear()
	_active_flares.clear()
	_doors.clear()
	_vents.clear()
	_pa_stations.clear()
	_holding_cage.clear()
	_glass_hazards.clear()
	_wheelchair_hazards.clear()
	_lockers.clear()
	_hide_desks.clear()
	_cabinets.clear()
	_flicker_lights.clear()
	_menu_cam = null
	_menu_stalker = null
	_snapshot_sent.clear()


# ===========================================================================
# 1. LIVE 3D MAIN MENU
# ===========================================================================
func enter_main_menu() -> void:
	phase = Phase.MAIN_MENU
	_jumpscare_active = false
	_clear_world()
	player.controls_enabled = false
	player.visible = false
	for pid in remote_listeners.keys():
		var rl := remote_listeners[pid] as RemoteListener
		if is_instance_valid(rl):
			rl.visible = false
			rl.set_process(false)
			var vp: Variant = rl.get("_voice_player")
			if vp is AudioStreamPlayer3D and is_instance_valid(vp):
				(vp as AudioStreamPlayer3D).stop()

	var dio := FloorGenerator.build_menu_diorama(world_container)
	_menu_cam = dio["camera"] as Camera3D
	_menu_stalker = dio["stalker"] as Node3D
	_flicker_lights = dio["flicker_lights"]
	if SynthAudio.has_method("set_menu_music"):
		SynthAudio.set_menu_music(true)
	SynthAudio.update_chase_music(1.0, false, 999.0)
	player.set_chase_tension(false, 999.0)
	hud.show_main_menu()


func _on_start_solo(diff: int) -> void:
	NetRelay.start_solo_mode()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	start_match(rng.randi_range(10000, 999999), diff)


func _on_start_coop_host(diff: int) -> void:
	if NetRelay.room_code.is_empty() or not NetRelay.is_host:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := rng.randi_range(10000, 999999)
	NetRelay.send_game_event("start_match", {"seed": s, "diff": diff})
	start_match(s, diff)


func _on_restart_requested() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := rng.randi_range(10000, 999999)
	if not NetRelay.room_code.is_empty() and NetRelay.is_host:
		NetRelay.send_game_event("start_match", {"seed": s, "diff": current_difficulty})
	start_match(s, current_difficulty)


# ===========================================================================
# 2. MATCH START & 14-ROOM FACILITY INITIALIZATION
# ===========================================================================
func start_match(seed_val: int, difficulty: int) -> void:
	_clear_world()
	_snapshot_sent.clear()
	phase = Phase.PLAYING
	if SynthAudio.has_method("set_menu_music"):
		SynthAudio.set_menu_music(false)
	_jumpscare_active = false
	current_seed = seed_val
	current_difficulty = difficulty
	match_elapsed_sec = 0.0

	safe_opened = false
	planks_removed = false
	cable_cut = false
	power_restored = false
	padlock_unlocked = false
	gate_opening = false
	_next_pickup_seq = 1

	_map_data = FloorGenerator.build_facility_map(world_container, seed_val)
	safe_code = str(_map_data["safe_code"])
	_doors = _map_data["doors"]
	_vents = _map_data["vents"]
	_pa_stations = _map_data["pa_stations"]
	_holding_cage = _map_data["holding_cage"]
	_glass_hazards = _map_data["glass_hazards"]
	_wheelchair_hazards = _map_data["wheelchair_hazards"]
	_lockers = _map_data["lockers"]
	_hide_desks = _map_data["hide_desks"]
	_cabinets = _map_data["cabinets"]
	_flicker_lights = _map_data["flicker_lights"]

	# Open Holding Cage door initially until someone is captured into it!
	_set_holding_cage_locked(false)

	for sp in _map_data["initial_spawns"]:
		_spawn_world_pickup(str(sp["item_id"]), sp["pos"], "init_" + str(_next_pickup_seq))

	var spawns: Array = _map_data["player_spawns"]
	var spawn_idx := 0
	if not NetRelay.room_code.is_empty() and not NetRelay.is_host:
		spawn_idx = clampi(NetRelay.peers.size(), 1, 3)
	player.visible = true
	player.reset_for_new_day(spawns[spawn_idx], true)
	if difficulty == SaveState.DIFF_NIGHTMARE:
		player.wounds = 1
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player.controls_enabled = true
	player.camera.make_current()

	var peer_idx := 1
	for pid in remote_listeners.keys():
		var rl := remote_listeners[pid] as RemoteListener
		if is_instance_valid(rl):
			var rl_idx := clampi(peer_idx, 1, 3)
			if rl_idx == spawn_idx:
				rl_idx = 0
			var rpos: Vector3 = spawns[rl_idx]
			rl.global_position = rpos
			rl._target_pos = rpos
			rl.set_process(true)
			rl.visible = not rl.is_hiding
			peer_idx += 1

	if not NetRelay.room_code.is_empty():
		player._sync_network(1.0)

	monster_director.spawn_stalker(
		_map_data["monster_spawn"],
		difficulty,
		_map_data["nav_nodes"],
		_map_data["nav_adj"],
		_doors,
		_lockers
	)

	hud.bind_minimap_world(
		monster_director,
		remote_listeners,
		_map_data["wall_segments"],
		_doors,
		_vents
	)
	hud.show_gameplay_hud()
	hud.update_objectives(false, false, false, false)
	hud.set_sector_name(FloorGenerator.get_sector_at(player.global_position, Loc.current_lang))
	_tut_start_pos = player.global_position
	_tut_prev_flashlight = player.flashlight_on
	_tut_prev_inv_count = 0
	hud.start_tutorial_if_needed(false)


func _set_holding_cage_locked(locked: bool) -> void:
	if _holding_cage.is_empty():
		return
	_holding_cage["is_locked"] = locked
	var piv := _holding_cage.get("door_pivot") as Node3D
	var dsh := _holding_cage.get("door_shape") as CollisionShape3D
	if piv != null:
		piv.rotation.y = 0.0 if locked else -1.48
	if dsh != null:
		dsh.disabled = not locked


func _spawn_world_pickup(item_id: String, pos: Vector3, custom_id: String = "") -> String:
	var pid := custom_id
	if pid.is_empty():
		pid = "pk_%s_%d" % [SaveState.player_id, _next_pickup_seq]
	_next_pickup_seq += 1

	if _world_pickups.has(pid):
		return pid

	var holder := Node3D.new()
	holder.position = pos
	dynamic_root.add_child(holder)

	var mdl := AssetLibrary.instantiate_model("item_" + item_id)
	holder.add_child(mdl)

	var sb := StaticBody3D.new()
	sb.position = Vector3(0, 0.14, 0)
	sb.set_meta("interact_type", "pickup")
	sb.set_meta("pickup_id", pid)
	sb.set_meta("item_id", item_id)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.48, 0.36, 0.48)
	cs.shape = box
	sb.add_child(cs)
	holder.add_child(sb)

	_world_pickups[pid] = {
		"node": holder,
		"item_id": item_id
	}
	return pid


# ===========================================================================
# 3. INTERACTIONS, VENTS, PA LURES, HOLDING CAGE & PUZZLES
# ===========================================================================
func _raycast_interactable(origin: Vector3, dir: Vector3) -> Node:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 3.1)
	q.collision_mask = 1 | 8 | 16
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var col := hit.get("collider") as Node
	if col != null and col.has_meta("interact_type"):
		return col
	return null


func _build_aim_prompt_for(col: Node) -> String:
	if player.is_downed:
		if player.has_item_in_inventory("syringe") >= 0:
			return Loc.t("PROMPT_SELF_REVIVE")
		return ""
	if player.is_hiding_in_locker:
		return Loc.t("PROMPT_EXIT_LOCKER")
	if col == null:
		return ""
	var itype := str(col.get_meta("interact_type"))
	var held := player.get_equipped_item()

	match itype:
		"pickup":
			var iid := str(col.get_meta("item_id"))
			var iname := (Loc.t("ITEM_code_note") % safe_code) if iid == "code_note" else Loc.t("ITEM_" + iid)
			return Loc.t("PROMPT_TAKE") % iname
		"door":
			var did := str(col.get_meta("door_id"))
			for d in _doors:
				if d["id"] == did:
					return Loc.t("PROMPT_DOOR_CLOSE" if bool(d["is_open"]) else "PROMPT_DOOR_OPEN")
		"vent":
			var vid := str(col.get_meta("vent_id"))
			if _vents.has(vid) and not bool(_vents[vid]["is_open"]):
				var has_driver := (held == "screwdriver" or player.has_item_in_inventory("screwdriver") >= 0)
				return Loc.t("PROMPT_VENT_UNSCREW" if has_driver else "PROMPT_VENT_FORCE")
		"pa_intercom":
			var paid := str(col.get_meta("pa_id"))
			if _pa_stations.has(paid):
				var cd := float(_pa_stations[paid]["cooldown"])
				if cd > 0.0:
					return Loc.t("PROMPT_PA_COOLDOWN") % int(ceil(cd))
				return Loc.t("PROMPT_PA_LURE")
		"cage_door":
			if not _holding_cage.is_empty() and bool(_holding_cage.get("is_locked", false)):
				return Loc.t("PROMPT_CAGE_UNLOCK")
		"locker":
			return Loc.t("PROMPT_HIDE_LOCKER")
		"cabinet":
			var cid := str(col.get_meta("cabinet_id"))
			if _cabinets.has(cid) and not bool(_cabinets[cid]["is_open"]):
				return Loc.t("PROMPT_SEARCH_DRAWER")
		"safe":
			return Loc.t("PROMPT_SAFE_OPENED") if safe_opened else Loc.t("PROMPT_SAFE_ENTER")
		"generator":
			if power_restored:
				return Loc.t("PROMPT_GEN_ONLINE")
			return Loc.t("PROMPT_GEN_INSERT") if held == "fuse" else Loc.t("PROMPT_GEN_NEED_FUSE")
		"exit_gate":
			if planks_removed and cable_cut and power_restored and padlock_unlocked:
				return Loc.t("PROMPT_EXIT_ESCAPE")
			if held == "crowbar" and not planks_removed:
				return Loc.t("PROMPT_EXIT_PRY")
			if held == "cutters" and not cable_cut:
				return Loc.t("PROMPT_EXIT_CUT")
			if held == "key" and not padlock_unlocked:
				return Loc.t("PROMPT_EXIT_UNLOCK")
			var rem := int(not planks_removed) + int(not cable_cut) + int(not power_restored) + int(not padlock_unlocked)
			return Loc.t("PROMPT_EXIT_LOCKED") % rem
		"ally":
			var pid := str(col.get_meta("peer_id"))
			if remote_listeners.has(pid) and (remote_listeners[pid] as RemoteListener).is_downed:
				return Loc.t("PROMPT_REVIVE_ALLY") % (remote_listeners[pid] as RemoteListener).callsign
	return ""


func _on_player_interact(aim_origin: Vector3, aim_dir: Vector3) -> void:
	if phase != Phase.PLAYING:
		return

	# Self-revive with Adrenaline Syringe when downed!
	if player.is_downed:
		if player.consume_item_by_id("syringe"):
			player.is_downed = false
			player.downed_timer = 90.0
			player.adrenaline_timer = 10.0
			SynthAudio.play_2d("item_pickup", 0.0, 1.35)
			hud.show_toast(Loc.t("TOAST_SYRINGE_USED"))
		return

	if player.is_hiding_in_locker:
		var lid := player.current_locker_id
		if _lockers.has(lid):
			var lk: Dictionary = _lockers[lid]
			lk["occupied"] = false
			var door_piv := lk.get("door_pivot") as Node3D
			if is_instance_valid(door_piv):
				door_piv.rotation.y = 0.0
			player.exit_locker(lk["exit_pos"])
			SynthAudio.play_3d("locker_clang", lk["exit_pos"], -5.0, 1.05)
			AcousticBus.emit_noise(lk["exit_pos"], 5.0, 0.25, "locker")
		return

	var col := _raycast_interactable(aim_origin, aim_dir)
	if col == null:
		player.try_use_held_consumable()
		return

	var itype := str(col.get_meta("interact_type"))
	var held := player.get_equipped_item()

	match itype:
		"pickup":
			var pid := str(col.get_meta("pickup_id"))
			var iid := str(col.get_meta("item_id"))
			if not _world_pickups.has(pid):
				return
			if not player.add_item_to_inventory(iid):
				hud.show_toast(Loc.t("PROMPT_INV_FULL"))
				return
			SynthAudio.play_2d("item_pickup", -3.0)
			_remove_world_pickup(pid)
			hud.advance_tutorial_if_step(2)
			NetRelay.send_game_event("pickup_taken", {"pid": pid, "iid": iid})
			if iid == "code_note":
				player.known_safe_code = safe_code
				hud.refresh_inventory_bar()
				hud.show_toast(Loc.t("TOAST_CODE_FOUND") % safe_code)
				NetRelay.send_game_event("note_shared", {"code": safe_code})

		"door":
			var did := str(col.get_meta("door_id"))
			_toggle_door(did, true)

		"vent":
			var vid := str(col.get_meta("vent_id"))
			var silent := (held == "screwdriver" or player.has_item_in_inventory("screwdriver") >= 0)
			_open_vent_hatch(vid, silent, true)

		"pa_intercom":
			var paid := str(col.get_meta("pa_id"))
			_trigger_pa_intercom(paid, true)

		"cage_door":
			_unlock_holding_cage(true)

		"locker":
			var lid := str(col.get_meta("locker_id"))
			if _lockers.has(lid):
				var lk: Dictionary = _lockers[lid]
				var prev_pos := player.global_position
				lk["occupied"] = true
				var door_piv := lk.get("door_pivot") as Node3D
				if is_instance_valid(door_piv):
					door_piv.rotation.y = 0.14
				player.enter_locker(lid, lk["inside_pos"], float(lk["look_yaw"]))
				SynthAudio.play_3d("locker_clang", lk["exit_pos"], -4.0)
				AcousticBus.emit_noise(lk["exit_pos"], 5.5, 0.28, "locker")
				monster_director.notify_player_hid_in_locker(lid, prev_pos)

		"cabinet":
			var cid := str(col.get_meta("cabinet_id"))
			_open_cabinet(cid, true)

		"safe":
			if not safe_opened:
				hud.open_safe_modal(player.known_safe_code)

		"generator":
			if not power_restored:
				if held == "fuse":
					player.consume_equipped_item()
					_activate_generator(true)
				else:
					hud.show_toast(Loc.t("PROMPT_GEN_NEED_FUSE"))

		"exit_gate":
			_interact_exit_gate(held)

		"ally":
			var peer_id := str(col.get_meta("peer_id"))
			if remote_listeners.has(peer_id) and (remote_listeners[peer_id] as RemoteListener).is_downed:
				var full_heal := false
				if held in ["medkit", "syringe"]:
					player.consume_equipped_item()
					full_heal = true
				SynthAudio.play_2d("item_pickup", -1.5, 1.2)
				NetRelay.send_game_event("revive_peer", {"target_id": peer_id, "heal": full_heal})


func _open_vent_hatch(vent_id: String, silent: bool, broadcast: bool) -> void:
	if not _vents.has(vent_id):
		return
	var v: Dictionary = _vents[vent_id]
	if bool(v["is_open"]):
		return
	v["is_open"] = true
	var sh := v.get("shape") as CollisionShape3D
	if sh != null:
		sh.disabled = true
	var ga := v.get("grate_a") as Node3D
	var gb := v.get("grate_b") as Node3D
	if ga != null:
		ga.visible = false
	if gb != null:
		gb.visible = false

	var wpos: Vector3 = v["world_pos"]
	if silent:
		SynthAudio.play_3d("vent_open", wpos + Vector3(0, 0.5, 0), -4.0)
		if broadcast:
			AcousticBus.emit_noise(wpos, 2.5, 0.12, "vent_silent")
	else:
		SynthAudio.play_3d("plank_rip", wpos + Vector3(0, 0.5, 0), 1.5, 1.2)
		if broadcast:
			AcousticBus.emit_noise(wpos, 15.5, 0.78, "vent_force")
	if broadcast:
		NetRelay.send_game_event("vent_open", {"id": vent_id, "silent": silent})


func _trigger_pa_intercom(pa_id: String, broadcast: bool) -> void:
	if not _pa_stations.has(pa_id):
		return
	var st: Dictionary = _pa_stations[pa_id]
	if float(st["cooldown"]) > 0.0:
		return
	st["cooldown"] = 25.0
	var target_pos: Vector3 = st["target_speaker_pos"]
	SynthAudio.play_2d("keypad_beep", -2.0, 1.15)
	SynthAudio.play_3d("pa_siren", target_pos, 4.0)
	hud.show_toast(Loc.t("TOAST_PA_TRIGGERED") % str(st["target_sector_name"]))
	if broadcast:
		AcousticBus.emit_noise(target_pos, 38.0, 1.0, "pa_siren")
		NetRelay.send_game_event("pa_lure", {"id": pa_id})
	else:
		monster_director.on_network_noise(target_pos, 38.0, "pa_siren")


func _unlock_holding_cage(broadcast: bool) -> void:
	if _holding_cage.is_empty() or not bool(_holding_cage.get("is_locked", false)):
		return
	_set_holding_cage_locked(false)
	player.is_caged = false
	var cpos: Vector3 = _holding_cage["outside_pos"]
	SynthAudio.play_3d("padlock_open", cpos + Vector3(0, 1.2, 0), -1.0)
	SynthAudio.play_3d("door_creak", cpos + Vector3(0, 1.2, 0), -2.0, 0.9)
	if broadcast:
		AcousticBus.emit_noise(cpos, 8.5, 0.42, "cage_latch")
		NetRelay.send_game_event("cage_unlocked", {})


func _on_door_smashed_nearby(door_pos: Vector3) -> void:
	var d := player.global_position.distance_to(door_pos)
	if d < 14.0:
		player.add_camera_trauma(clampf(1.0 - d / 14.0, 0.25, 0.85))


func _remove_world_pickup(pid: String) -> void:
	if _world_pickups.has(pid):
		var n := _world_pickups[pid]["node"] as Node3D
		if is_instance_valid(n):
			n.queue_free()
		_world_pickups.erase(pid)


func _toggle_door(door_id: String, broadcast: bool) -> void:
	for d in _doors:
		if d["id"] == door_id:
			var next_open := not bool(d["is_open"])
			d["is_open"] = next_open
			d["target_angle"] = -1.52 if next_open else 0.0
			SynthAudio.play_3d("door_creak", d["world_pos"] + Vector3(0, 1.2, 0), -3.0)
			if broadcast:
				AcousticBus.emit_noise(d["world_pos"], 6.0, 0.30, "door")
				NetRelay.send_game_event("door_toggle", {"id": door_id, "open": next_open})
			break


func _open_cabinet(cab_id: String, broadcast: bool) -> void:
	if not _cabinets.has(cab_id):
		return
	var c: Dictionary = _cabinets[cab_id]
	if bool(c["is_open"]):
		return
	c["is_open"] = true
	var dp := c["drawer_pivot"] as Node3D
	if dp != null:
		dp.position.z -= 0.34
	SynthAudio.play_3d("drawer_slide", (c["node"] as Node3D).global_position + Vector3(0, 0.7, 0), -3.0)
	var loot := str(c["loot_item"])
	if not loot.is_empty():
		_spawn_world_pickup(loot, c["item_spawn_pos"], "cab_loot_" + cab_id)
	if broadcast:
		AcousticBus.emit_noise((c["node"] as Node3D).global_position, 5.5, 0.25, "drawer")
		NetRelay.send_game_event("cabinet_open", {"id": cab_id})


func _on_safe_code_submitted(entered: String) -> void:
	if entered == safe_code:
		hud.close_safe_modal()
		_unlock_safe(true)
	else:
		SynthAudio.play_2d("keypad_error", 0.0)
		if _map_data.has("safe_key_pos"):
			AcousticBus.emit_noise(_map_data["safe_key_pos"], 16.0, 0.78, "alarm")


func _unlock_safe(broadcast: bool) -> void:
	if safe_opened:
		return
	safe_opened = true
	var snode := _map_data.get("safe_node") as Node3D
	if snode != null:
		var spiv := AssetLibrary.find_child_by_prefix(snode, "SafeDoorPivot") as Node3D
		if spiv != null:
			spiv.rotation.y = -1.65
	var kpos: Vector3 = _map_data["safe_key_pos"]
	_spawn_world_pickup("key", kpos + Vector3(-0.35, -0.04, 0.0), "safe_master_key")
	SynthAudio.play_3d("padlock_open", kpos, 0.0)
	if broadcast:
		NetRelay.send_game_event("safe_unlocked", {})


func _activate_generator(broadcast: bool) -> void:
	if power_restored:
		return
	power_restored = true
	var gnode := _map_data.get("generator_node") as Node3D
	if gnode != null:
		var finst := AssetLibrary.find_child_by_prefix(gnode, "FuseInstalled") as Node3D
		if finst != null:
			finst.scale = Vector3.ONE
		var lpiv := AssetLibrary.find_child_by_prefix(gnode, "LeverPivot") as Node3D
		if lpiv != null:
			lpiv.rotation.x = 0.85
		SynthAudio.play_3d("generator_on", gnode.global_position + Vector3(0, 1.0, 0), 1.5)
		if broadcast:
			AcousticBus.emit_noise(gnode.global_position, 20.0, 0.85, "generator")

	var gate := _map_data.get("exit_gate") as Node3D
	if gate != null:
		var sr := AssetLibrary.find_child_by_prefix(gate, "StatusRed") as Node3D
		var sg := AssetLibrary.find_child_by_prefix(gate, "StatusGreen") as Node3D
		if sr != null:
			sr.visible = false
		if sg != null:
			sg.scale = Vector3.ONE
	_sync_escape_ui()
	if broadcast:
		NetRelay.send_game_event("lock_cleared", {"which": "power"})


func _interact_exit_gate(held: String) -> void:
	var gate := _map_data.get("exit_gate") as Node3D
	if gate == null:
		return
	var gate_pos := gate.global_position

	if planks_removed and cable_cut and power_restored and padlock_unlocked:
		_trigger_victory(true)
		return

	if held == "crowbar" and not planks_removed:
		planks_removed = true
		var pl := AssetLibrary.find_child_by_prefix(gate, "LockPlanks") as Node3D
		if pl != null:
			pl.visible = false
		SynthAudio.play_3d("plank_rip", gate_pos + Vector3(0, 1.3, 0), 2.5)
		AcousticBus.emit_noise(gate_pos, 25.0, 0.96, "plank_rip")
		NetRelay.send_game_event("lock_cleared", {"which": "planks"})
		_sync_escape_ui()
	elif held == "cutters" and not cable_cut:
		cable_cut = true
		var cb := AssetLibrary.find_child_by_prefix(gate, "LockCable") as Node3D
		if cb != null:
			cb.visible = false
		SynthAudio.play_3d("wire_snip", gate_pos + Vector3(0, 1.3, 0), 0.0)
		AcousticBus.emit_noise(gate_pos, 12.0, 0.58, "wire_snip")
		NetRelay.send_game_event("lock_cleared", {"which": "cable"})
		_sync_escape_ui()
	elif held == "key" and not padlock_unlocked:
		padlock_unlocked = true
		player.consume_equipped_item()
		var pd := AssetLibrary.find_child_by_prefix(gate, "LockPadlock") as Node3D
		if pd != null:
			pd.visible = false
		SynthAudio.play_3d("padlock_open", gate_pos + Vector3(0, 1.3, 0), 0.0)
		AcousticBus.emit_noise(gate_pos, 8.5, 0.40, "padlock")
		NetRelay.send_game_event("lock_cleared", {"which": "padlock"})
		_sync_escape_ui()
	else:
		var rem := int(not planks_removed) + int(not cable_cut) + int(not power_restored) + int(not padlock_unlocked)
		hud.show_toast(Loc.t("PROMPT_EXIT_LOCKED") % rem)


func _sync_escape_ui() -> void:
	hud.update_objectives(planks_removed, cable_cut, power_restored, padlock_unlocked)


func _trigger_victory(broadcast: bool) -> void:
	if phase != Phase.PLAYING:
		return
	phase = Phase.ENDED
	gate_opening = true
	SynthAudio.update_chase_music(1.0, false, 999.0)
	player.set_chase_tension(false, 999.0)
	SynthAudio.play_2d("victory_airlock", 2.0)
	monster_director.clear_stalker()
	SaveState.record_escape(match_elapsed_sec)
	if broadcast:
		NetRelay.send_game_event("victory", {"elapsed": match_elapsed_sec})
	hud.show_end_screen(true, match_elapsed_sec)


# ===========================================================================
# 4. THROWN BOTTLES, SONIC STROBE FLARES & FLOOR SOUND HAZARDS
# ===========================================================================
func _on_player_item_dropped(item_id: String, origin: Vector3, vel: Vector3, is_bottle: bool) -> void:
	_spawn_flying_item(item_id, origin, vel, is_bottle, false, true)
	NetRelay.send_game_event("item_tossed", {
		"iid": item_id,
		"pos": [origin.x, origin.y, origin.z],
		"vel": [vel.x, vel.y, vel.z],
		"bottle": is_bottle,
		"flare": false
	})


func _on_player_flare_deployed(origin: Vector3, vel: Vector3) -> void:
	_spawn_flying_item("flare", origin, vel, false, true, true)
	NetRelay.send_game_event("item_tossed", {
		"iid": "flare",
		"pos": [origin.x, origin.y, origin.z],
		"vel": [vel.x, vel.y, vel.z],
		"bottle": false,
		"flare": true
	})


func _spawn_flying_item(item_id: String, origin: Vector3, vel: Vector3, is_bottle: bool, is_flare: bool, is_local_owner: bool) -> void:
	var n := AssetLibrary.instantiate_model("item_" + item_id)
	n.position = origin
	dynamic_root.add_child(n)
	_flying_items.append({
		"node": n,
		"item_id": item_id,
		"vel": vel,
		"is_bottle": is_bottle,
		"is_flare": is_flare,
		"local": is_local_owner
	})


func _ignite_flare_at(land_pos: Vector3) -> void:
	var fholder := Node3D.new()
	fholder.position = land_pos
	dynamic_root.add_child(fholder)

	var fmesh := AssetLibrary.instantiate_model("item_flare")
	fholder.add_child(fmesh)

	var fl := OmniLight3D.new()
	fl.position = Vector3(0, 0.25, 0)
	fl.light_color = Color(1.0, 0.22, 0.16)
	fl.light_energy = 3.2
	fl.omni_range = 11.5
	fholder.add_child(fl)

	SynthAudio.play_3d("flare_stun", land_pos + Vector3(0, 0.2, 0), 3.0)
	monster_director.stun_with_flare(land_pos, 10.5)
	_active_flares.append({"node": fholder, "light": fl, "timer": 6.5})


func _update_flying_items_and_flares(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var i := _flying_items.size() - 1
	while i >= 0:
		var f: Dictionary = _flying_items[i]
		var n := f["node"] as Node3D
		var vel: Vector3 = f["vel"]
		vel.y -= 16.0 * delta
		var cur := n.global_position
		var nxt := cur + vel * delta
		n.rotate_x(delta * 6.0)

		var q := PhysicsRayQueryParameters3D.create(cur, nxt)
		q.collision_mask = 1 | 16
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() or nxt.y <= 0.06:
			var land_pos := (hit["position"] as Vector3) if not hit.is_empty() else Vector3(nxt.x, 0.05, nxt.z)
			land_pos.y = maxf(0.05, land_pos.y)
			n.queue_free()
			_flying_items.remove_at(i)

			if bool(f["is_flare"]):
				_ignite_flare_at(Vector3(land_pos.x, 0.05, land_pos.z))
			elif bool(f["is_bottle"]):
				SynthAudio.play_3d("bottle_shatter", land_pos, 3.0)
				if bool(f["local"]):
					AcousticBus.emit_noise(land_pos, 28.0, 1.0, "bottle_shatter")
			else:
				SynthAudio.play_3d("item_clatter", land_pos, -1.0)
				var pid := _spawn_world_pickup(str(f["item_id"]), Vector3(land_pos.x, 0.05, land_pos.z))
				if bool(f["local"]):
					AcousticBus.emit_noise(land_pos, 12.0, 0.65, "tool_drop")
					NetRelay.send_game_event("spawn_pickup", {
						"pid": pid,
						"iid": str(f["item_id"]),
						"pos": [land_pos.x, 0.05, land_pos.z]
					})
		else:
			f["vel"] = vel
			n.global_position = nxt
		i -= 1

	var fi := _active_flares.size() - 1
	var t_now := Time.get_ticks_msec() * 0.001
	while fi >= 0:
		var af: Dictionary = _active_flares[fi]
		af["timer"] = float(af["timer"]) - delta
		var lgt := af["light"] as OmniLight3D
		if is_instance_valid(lgt):
			lgt.light_energy = 2.6 + 1.1 * sin(t_now * 28.0)
		if float(af["timer"]) <= 0.0:
			var fn := af["node"] as Node3D
			if is_instance_valid(fn):
				fn.queue_free()
			_active_flares.remove_at(fi)
		fi -= 1


func _update_sound_hazards_and_pa(delta: float) -> void:
	for paid in _pa_stations.keys():
		var st: Dictionary = _pa_stations[paid]
		if float(st["cooldown"]) > 0.0:
			st["cooldown"] = maxf(0.0, float(st["cooldown"]) - delta)

	var p_pos := player.global_position
	var spd_2d := Vector2(player.velocity.x, player.velocity.z).length()

	# Broken glass shards: walking/running upright crunches loudly, crouching sneaks safely!
	for gh in _glass_hazards:
		gh["cooldown"] = maxf(0.0, float(gh["cooldown"]) - delta)
		if float(gh["cooldown"]) <= 0.0 and spd_2d > 0.45 and not player.is_crouching and not player.is_downed:
			var gp: Vector3 = gh["pos"]
			if Vector2(p_pos.x - gp.x, p_pos.z - gp.z).length() <= float(gh["radius"]):
				gh["cooldown"] = 1.6
				SynthAudio.play_3d("glass_crunch", gp + Vector3(0, 0.05, 0), 1.5)
				AcousticBus.emit_noise(gp, 16.5, 0.82, "glass_crunch")

	# Rusted wheelchairs: bumping into one nudges it & squeaks!
	for wh in _wheelchair_hazards:
		wh["cooldown"] = maxf(0.0, float(wh["cooldown"]) - delta)
		if float(wh["cooldown"]) <= 0.0 and spd_2d > 0.35:
			var wp: Vector3 = wh["pos"]
			var diff2 := Vector2(p_pos.x - wp.x, p_pos.z - wp.z)
			if diff2.length() <= float(wh["radius"]):
				wh["cooldown"] = 2.4
				var wnode := wh["node"] as Node3D
				if is_instance_valid(wnode):
					wnode.rotate_y(randf_range(-0.28, 0.28))
				SynthAudio.play_3d("wheelchair_squeak", wp + Vector3(0, 0.4, 0), 1.0)
				AcousticBus.emit_noise(wp, 14.0, 0.72, "wheelchair")


# ===========================================================================
# 5. TIME-FREE WOUNDS, SURGICAL HOLDING CAGE & CO-OP TEAMMATE RESCUE
# ===========================================================================
func _reset_player_jumpscare_camera() -> void:
	if player == null or not is_instance_valid(player):
		return
	player._cam_trauma = 0.0
	player._cam_roll = 0.0
	if player.head != null and is_instance_valid(player.head):
		player.head.rotation.x = 0.0
	if player.camera != null and is_instance_valid(player.camera):
		player.camera.fov = ListenerPlayer.BASE_FOV
		player.camera.position = Vector3.ZERO
		player.camera.rotation = Vector3.ZERO
		player.camera.h_offset = 0.0
		player.camera.v_offset = 0.0


func _play_catch_jumpscare() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var duration := 0.85
	var elapsed := 0.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	while elapsed < duration:
		if not is_inside_tree() or phase != Phase.PLAYING or not _jumpscare_active:
			return
		var dt := get_process_delta_time()
		elapsed += dt
		if player != null and is_instance_valid(player) and player.camera != null and is_instance_valid(player.camera) and player.camera.is_inside_tree():
			if SaveState.reduce_motion:
				player.camera.fov = 50.0
			else:
				var fov_t := clampf(elapsed / 0.11, 0.0, 1.0)
				var ease_out := 1.0 - pow(1.0 - fov_t, 3.0)
				player.camera.fov = lerpf(ListenerPlayer.BASE_FOV, 50.0, ease_out)
			player.camera.h_offset = 0.0
			player.camera.v_offset = 0.0
			if monster_director != null and is_instance_valid(monster_director) and monster_director.stalker_node != null and is_instance_valid(monster_director.stalker_node):
				var head_target := monster_director.get_jumpscare_head_world_pos()
				var to_head := head_target - player.camera.global_position
				if to_head.length_squared() > 0.001:
					var dir := to_head.normalized()
					var up_vec := Vector3.UP
					if absf(dir.dot(Vector3.UP)) > 0.99:
						up_vec = Vector3.FORWARD if absf(dir.dot(Vector3.FORWARD)) <= 0.99 else Vector3.RIGHT
					player.camera.look_at(head_target, up_vec)
			if not SaveState.reduce_motion:
				var decay := 1.0 - 0.35 * clampf(elapsed / duration, 0.0, 1.0)
				var pitch_shake := clampf((sin(elapsed * 53.0) * 0.018 + rng.randf_range(-0.007, 0.007)) * decay, -0.03, 0.03)
				var yaw_shake := clampf((cos(elapsed * 47.0) * 0.016 + rng.randf_range(-0.007, 0.007)) * decay, -0.03, 0.03)
				var roll_shake := clampf(sin(elapsed * 61.0) * 0.014 * decay, -0.03, 0.03)
				player.camera.rotate_object_local(Vector3.RIGHT, pitch_shake)
				player.camera.rotate_object_local(Vector3.UP, yaw_shake)
				player.camera.rotate_object_local(Vector3.FORWARD, roll_shake)
		await get_tree().process_frame


func _on_local_player_caught() -> void:
	if phase != Phase.PLAYING or _jumpscare_active or player == null or not is_instance_valid(player) or player.is_downed or player.is_dead:
		return
	for lid in _lockers.keys():
		var lk_item: Dictionary = _lockers[lid]
		if not bool(lk_item.get("occupied", false)):
			var dpiv := lk_item.get("door_pivot") as Node3D
			if is_instance_valid(dpiv):
				dpiv.rotation.y = 0.0
	_jumpscare_active = true
	player.controls_enabled = false
	player.velocity = Vector3.ZERO
	player._cam_trauma = 0.0

	SynthAudio.play_2d("jumpscare_screech", 3.5)
	SynthAudio.play_2d("catch_slam", 3.0)
	if monster_director != null and is_instance_valid(monster_director) and player.camera != null and is_instance_valid(player.camera):
		monster_director.trigger_jumpscare_pose(player.camera)
	hud.play_jumpscare_flash(0.85)
	if SaveState.haptics_enabled and OS.get_name() == "Android":
		Input.vibrate_handheld(260)

	await _play_catch_jumpscare()
	if not is_inside_tree() or not is_instance_valid(player):
		return

	if monster_director != null and is_instance_valid(monster_director):
		monster_director.end_jumpscare_pose()
	_reset_player_jumpscare_camera()
	_jumpscare_active = false

	if phase != Phase.PLAYING:
		return

	# Co-op Mode: Enter downed crawling state so friends can revive you (or self-revive with Syringe!)
	if not NetRelay.room_code.is_empty() and _any_remote_teammate_active():
		player.is_downed = true
		player.downed_timer = 90.0
		player.controls_enabled = true
		return

	# Solo (or last standing survivor): If not yet critically wounded, Specimen-07 locks you in the Surgical Holding Cage!
	if player.wounds < 1:
		_capture_into_holding_cage()
	else:
		_trigger_game_over()


func _any_remote_teammate_active() -> bool:
	for pid in remote_listeners.keys():
		var rp: RemoteListener = remote_listeners[pid]
		if is_instance_valid(rp) and not rp.is_downed and not rp.is_frozen:
			return true
	return false


func _first_downed_ally_name() -> String:
	for pid in remote_listeners.keys():
		var rp: RemoteListener = remote_listeners[pid]
		if is_instance_valid(rp) and (rp.is_downed or rp.is_caged):
			return rp.callsign
	return ""


func _capture_into_holding_cage() -> void:
	phase = Phase.TRANSITION
	SynthAudio.update_chase_music(1.0, false, 999.0)
	player.set_chase_tension(false, 999.0)
	player.wounds += 1
	player.is_downed = false
	player.is_caged = true
	player.controls_enabled = false
	hud.show_cage_curtain(true)

	await get_tree().create_timer(2.0).timeout
	if not is_inside_tree():
		return

	var cage_in: Vector3 = _holding_cage.get("inside_pos", Vector3(-30.5, 0.08, 11.8))
	_set_holding_cage_locked(true)
	NetRelay.send_game_event("cage_locked", {})

	player.reset_for_new_day(cage_in, false) # Preserves all inventory items & unlocked airlock seals!
	player.is_caged = true
	player.rotation.y = -PI * 0.5 # Face +X out through the iron cage bars!
	monster_director.reset_after_catch(_map_data["monster_spawn"])
	hud.show_cage_curtain(false)
	if player.has_method("start_cage_wakeup"):
		player.start_cage_wakeup(2.2)
	if hud.has_method("play_cage_wakeup_effect"):
		hud.play_cage_wakeup_effect(2.5)
	player.controls_enabled = true
	phase = Phase.PLAYING


func _trigger_game_over() -> void:
	phase = Phase.ENDED
	SynthAudio.update_chase_music(1.0, false, 999.0)
	player.set_chase_tension(false, 999.0)
	player.is_dead = true
	player.controls_enabled = false
	monster_director.clear_stalker()
	hud.show_end_screen(false, match_elapsed_sec)


# ===========================================================================
# 6. RUNTIME LOOP & CO-OP REPLICATION
# ===========================================================================
func _process(delta: float) -> void:
	var t_now := Time.get_ticks_msec() * 0.001
	for fl in _flicker_lights:
		var omni := fl["light"] as OmniLight3D
		if is_instance_valid(omni):
			var ph := float(fl["phase"])
			var wave := sin(t_now * 7.3 + ph) * sin(t_now * 19.1 + ph * 2.0)
			omni.light_energy = float(fl["base_energy"]) * (0.55 if wave > 0.72 else 1.0)

	if phase == Phase.MAIN_MENU:
		_menu_time += delta
		if _menu_cam != null:
			_menu_cam.position.x = -0.15 + sin(_menu_time * 0.55) * 0.08
			_menu_cam.position.y = 1.48 + cos(_menu_time * 0.42) * 0.04
		return

	if gate_opening and _map_data.has("exit_gate"):
		var gate := _map_data["exit_gate"] as Node3D
		if is_instance_valid(gate):
			var dl := AssetLibrary.find_child_by_prefix(gate, "DoorLeft") as Node3D
			var dr := AssetLibrary.find_child_by_prefix(gate, "DoorRight") as Node3D
			if dl != null:
				dl.position.x = move_toward(dl.position.x, -1.15, delta * 1.2)
			if dr != null:
				dr.position.x = move_toward(dr.position.x, 1.15, delta * 1.2)

	if phase != Phase.PLAYING:
		return

	match_elapsed_sec += delta

	for d in _doors:
		var piv := d["pivot"] as Node3D
		if is_instance_valid(piv):
			d["angle"] = move_toward(float(d["angle"]), float(d["target_angle"]), delta * 5.4)
			piv.rotation.y = float(d["angle"])

	var under := false
	for box in _hide_desks:
		if box.has_point(player.global_position + Vector3(0, 0.35, 0)):
			under = true
			break
	player.is_under_desk = under

	if player.is_downed:
		player.downed_timer -= delta
		if player.downed_timer <= 0.0:
			if player.wounds < 1:
				_capture_into_holding_cage()
			elif not _any_remote_teammate_active():
				_trigger_game_over()
			else:
				_capture_into_holding_cage()
			return
		elif not _any_remote_teammate_active() and player.has_item_in_inventory("syringe") < 0:
			if player.wounds < 1:
				_capture_into_holding_cage()
			else:
				_trigger_game_over()
			return

	_update_flying_items_and_flares(delta)
	_update_sound_hazards_and_pa(delta)

	var col := _raycast_interactable(player.camera.global_position, -player.camera.global_transform.basis.z)
	hud.set_aim_prompt(_build_aim_prompt_for(col))

	var s_dist := monster_director.get_distance_to_local_player()
	var in_chase := (monster_director.state == MonsterDirector.STATE_CHASE)
	SynthAudio.update_tension_heartbeat(delta, s_dist, in_chase)
	SynthAudio.update_chase_music(delta, in_chase, s_dist)
	player.set_chase_tension(in_chase, s_dist)
	hud.set_sector_name(FloorGenerator.get_sector_at(player.global_position, Loc.current_lang))
	_update_tutorial_progression()
	hud.update_runtime_hud(delta, current_difficulty, monster_director.state, s_dist, _first_downed_ally_name())


func _update_tutorial_progression() -> void:
	if not hud.is_tutorial_active() or player == null:
		return
	var moved_dist := Vector2(player.global_position.x - _tut_start_pos.x, player.global_position.z - _tut_start_pos.z).length()
	if player.is_crouching or moved_dist > 2.5:
		hud.advance_tutorial_if_step(1)

	var inv_count := 0
	for s_item in player.inventory:
		if not s_item.is_empty():
			inv_count += 1
	if player.flashlight_on != _tut_prev_flashlight or inv_count > _tut_prev_inv_count:
		hud.advance_tutorial_if_step(2)
	_tut_prev_flashlight = player.flashlight_on
	_tut_prev_inv_count = inv_count

	if player.is_holding_breath or player.is_hiding_in_locker:
		hud.advance_tutorial_if_step(3)


func _on_language_changed(_lang: String) -> void:
	if phase == Phase.PLAYING and player != null and hud != null:
		hud.set_sector_name(FloorGenerator.get_sector_at(player.global_position, Loc.current_lang))


func _on_peer_updated(peer_id: String, state: Dictionary) -> void:
	var is_new := not remote_listeners.has(peer_id)
	if is_new:
		var rl := RemoteListener.new()
		rl.peer_id = peer_id
		add_child(rl)
		if phase == Phase.MAIN_MENU:
			rl.visible = false
			rl.set_process(false)
		remote_listeners[peer_id] = rl
		# Late-join friend: hand them the full live match state so they drop into the ongoing descent!
		if NetRelay.is_host and phase != Phase.MAIN_MENU and not _snapshot_sent.has(peer_id):
			_snapshot_sent[peer_id] = true
			NetRelay.send_game_event("match_snapshot", _build_match_snapshot())
	(remote_listeners[peer_id] as RemoteListener).apply_network_state(state)


func _build_match_snapshot() -> Dictionary:
	var open_doors: Array[String] = []
	for d in _doors:
		if bool(d["is_open"]):
			open_doors.append(str(d["id"]))
	var open_vents: Array[String] = []
	for vid in _vents.keys():
		if bool(_vents[vid]["is_open"]):
			open_vents.append(str(vid))
	var open_cabs: Array[String] = []
	for cid in _cabinets.keys():
		if bool(_cabinets[cid]["is_open"]):
			open_cabs.append(str(cid))
	var pickups: Array[Dictionary] = []
	for pid in _world_pickups.keys():
		var n := _world_pickups[pid]["node"] as Node3D
		var p := n.global_position if is_instance_valid(n) else Vector3.ZERO
		pickups.append({
			"pid": str(pid),
			"iid": str(_world_pickups[pid]["item_id"]),
			"pos": [p.x, p.y, p.z]
		})
	return {
		"seed": current_seed,
		"diff": current_difficulty,
		"elapsed": match_elapsed_sec,
		"planks": planks_removed,
		"cable": cable_cut,
		"power": power_restored,
		"padlock": padlock_unlocked,
		"safe": safe_opened,
		"cage": bool(_holding_cage.get("is_locked", false)),
		"doors": open_doors,
		"vents": open_vents,
		"cabs": open_cabs,
		"pickups": pickups,
		"ended": phase == Phase.ENDED,
		"victory": gate_opening
	}


func _apply_match_snapshot(d: Dictionary) -> void:
	start_match(int(d.get("seed", current_seed)), int(d.get("diff", current_difficulty)))
	match_elapsed_sec = float(d.get("elapsed", 0.0))
	for did in d.get("doors", []):
		for dd in _doors:
			if str(dd["id"]) == str(did):
				dd["is_open"] = true
				dd["angle"] = -1.52
				dd["target_angle"] = -1.52
				var piv := dd["pivot"] as Node3D
				if is_instance_valid(piv):
					piv.rotation.y = -1.52
	for vid in d.get("vents", []):
		_open_vent_hatch(str(vid), true, false)
	for cid in d.get("cabs", []):
		_open_cabinet(str(cid), false)
	if bool(d.get("safe", false)):
		_unlock_safe(false)
	if bool(d.get("power", false)):
		_activate_generator(false)
	planks_removed = bool(d.get("planks", false))
	cable_cut = bool(d.get("cable", false))
	padlock_unlocked = bool(d.get("padlock", false))
	var gate := _map_data.get("exit_gate") as Node3D
	if gate != null:
		var pl := AssetLibrary.find_child_by_prefix(gate, "LockPlanks") as Node3D
		if pl != null:
			pl.visible = not planks_removed
		var cb := AssetLibrary.find_child_by_prefix(gate, "LockCable") as Node3D
		if cb != null:
			cb.visible = not cable_cut
		var pd := AssetLibrary.find_child_by_prefix(gate, "LockPadlock") as Node3D
		if pd != null:
			pd.visible = not padlock_unlocked
	_set_holding_cage_locked(bool(d.get("cage", false)))
	for pid in _world_pickups.keys():
		_remove_world_pickup(str(pid))
	for p in d.get("pickups", []):
		if typeof(p) == TYPE_DICTIONARY and typeof(p.get("pos")) == TYPE_ARRAY and (p["pos"] as Array).size() >= 3:
			var a: Array = p["pos"]
			_spawn_world_pickup(str(p.get("iid", "bottle")), Vector3(float(a[0]), float(a[1]), float(a[2])), str(p.get("pid", "")))
	_sync_escape_ui()
	hud.show_toast(Loc.t("TOAST_MP_SYNC"))
	if bool(d.get("ended", false)):
		if bool(d.get("victory", false)):
			_trigger_victory(false)
		else:
			_trigger_game_over()


func _clear_remote_listeners() -> void:
	for pid in remote_listeners.keys():
		var rl := remote_listeners[pid] as RemoteListener
		if is_instance_valid(rl):
			rl.queue_free()
	remote_listeners.clear()


func _on_room_left(_reason: String) -> void:
	_clear_remote_listeners()


func _on_host_migrated(new_host_id: String, _new_host_name: String) -> void:
	if phase == Phase.PLAYING and new_host_id == SaveState.player_id and monster_director != null:
		if current_difficulty != SaveState.DIFF_PRACTICE:
			if not monster_director.active or monster_director.stalker_node == null:
				monster_director.spawn_stalker(
					_map_data["monster_spawn"],
					current_difficulty,
					_map_data["nav_nodes"],
					_map_data["nav_adj"],
					_doors,
					_lockers
				)
			else:
				monster_director.active = true
				monster_director.state = MonsterDirector.STATE_PATROL
				monster_director._pick_next_patrol_target()


func _on_peer_removed(peer_id: String) -> void:
	if remote_listeners.has(peer_id):
		var rl := remote_listeners[peer_id] as RemoteListener
		if is_instance_valid(rl):
			rl.queue_free()
		remote_listeners.erase(peer_id)


func _on_peer_voice(peer_id: String, pcm8: PackedByteArray, _lvl: float) -> void:
	if phase == Phase.MAIN_MENU:
		return
	if remote_listeners.has(peer_id):
		(remote_listeners[peer_id] as RemoteListener).play_voice_packet(pcm8)


func _on_remote_event(_from_id: String, ev: String, data: Dictionary) -> void:
	match ev:
		"start_match":
			start_match(int(data.get("seed", 10707)), int(data.get("diff", SaveState.DIFF_NORMAL)))
		"match_snapshot":
			_apply_match_snapshot(data)
		"stalker_sync":
			monster_director.apply_remote_stalker_state(data)
		"noise":
			if typeof(data.get("pos")) == TYPE_ARRAY and data["pos"].size() >= 3:
				var p: Array = data["pos"]
				monster_director.on_network_noise(Vector3(float(p[0]), float(p[1]), float(p[2])), float(data.get("r", 10.0)), str(data.get("tag", "")))
		"door_toggle":
			var did := str(data.get("id", ""))
			for d in _doors:
				if d["id"] == did:
					d["is_open"] = bool(data.get("open", true))
					d["target_angle"] = -1.52 if bool(d["is_open"]) else 0.0
		"vent_open":
			_open_vent_hatch(str(data.get("id", "")), bool(data.get("silent", true)), false)
		"pa_lure":
			_trigger_pa_intercom(str(data.get("id", "")), false)
		"cage_locked":
			_set_holding_cage_locked(true)
		"cage_unlocked":
			_unlock_holding_cage(false)
		"cabinet_open":
			_open_cabinet(str(data.get("id", "")), false)
		"pickup_taken":
			_remove_world_pickup(str(data.get("pid", "")))
		"spawn_pickup":
			if typeof(data.get("pos")) == TYPE_ARRAY and data["pos"].size() >= 3:
				var p: Array = data["pos"]
				_spawn_world_pickup(str(data.get("iid", "bottle")), Vector3(float(p[0]), float(p[1]), float(p[2])), str(data.get("pid", "")))
		"item_tossed":
			if typeof(data.get("pos")) == TYPE_ARRAY and typeof(data.get("vel")) == TYPE_ARRAY:
				var p: Array = data["pos"]
				var v: Array = data["vel"]
				_spawn_flying_item(
					str(data.get("iid", "bottle")),
					Vector3(float(p[0]), float(p[1]), float(p[2])),
					Vector3(float(v[0]), float(v[1]), float(v[2])),
					bool(data.get("bottle", false)),
					bool(data.get("flare", false)),
					false
				)
		"note_shared":
			player.known_safe_code = str(data.get("code", safe_code))
			hud.refresh_inventory_bar()
			hud.show_toast(Loc.t("TOAST_CODE_FOUND") % player.known_safe_code)
		"safe_unlocked":
			_unlock_safe(false)
		"lock_cleared":
			var w := str(data.get("which", ""))
			var gate := _map_data.get("exit_gate") as Node3D
			if w == "power":
				_activate_generator(false)
			elif w == "planks":
				planks_removed = true
				if gate != null:
					var pl := AssetLibrary.find_child_by_prefix(gate, "LockPlanks") as Node3D
					if pl != null:
						pl.visible = false
				_sync_escape_ui()
			elif w == "cable":
				cable_cut = true
				if gate != null:
					var cb := AssetLibrary.find_child_by_prefix(gate, "LockCable") as Node3D
					if cb != null:
						cb.visible = false
				_sync_escape_ui()
			elif w == "padlock":
				padlock_unlocked = true
				if gate != null:
					var pd := AssetLibrary.find_child_by_prefix(gate, "LockPadlock") as Node3D
					if pd != null:
						pd.visible = false
				_sync_escape_ui()
		"stalker_caught_peer":
			if str(data.get("target_id", "")) == SaveState.player_id:
				_on_local_player_caught()
		"revive_peer":
			if str(data.get("target_id", "")) == SaveState.player_id and player.is_downed:
				player.is_downed = false
				player.downed_timer = 90.0
				if bool(data.get("heal", false)):
					player.wounds = 0
				else:
					player.wounds = max(1, player.wounds)
				SynthAudio.play_2d("item_pickup", 0.0, 1.3)
		"victory":
			_trigger_victory(false)
